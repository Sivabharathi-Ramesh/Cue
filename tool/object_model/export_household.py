"""Build Cue's household detector from the calibrated YOLOE-26s LiteRT base.

The checkpoint and the compatible MobileCLIP weights are export-time inputs.
The app receives the fused LiteRT model and runs it offline.

With --reference-photos, use a JSON array of records with label, file, and
box. Each box is [left, top, right, bottom] in the upright photo, scaled to 0–1.
Relative file paths are resolved from the manifest's directory.
Use the existing household model as --base to update only those labels.
"""

import argparse
import base64
import csv
import json
from collections import defaultdict
from pathlib import Path
from tempfile import NamedTemporaryFile
from zipfile import ZipFile

import flatbuffers
import numpy as np
import torch
from ai_edge_litert import schema_py_generated as schema
from ultralytics import YOLOE


MANIFEST = Path(__file__).with_name("household_labels.tsv")
CALIBRATION = Path(__file__).with_name("calibrated_classes.json")
HEAD_SIDES = (80, 40, 20)
ANCHORS = sum(side * side for side in HEAD_SIDES)


def read_labels():
    with MANIFEST.open(encoding="utf-8") as manifest:
        entries = list(csv.reader(
            (line for line in manifest if line.strip() and not line.startswith("#")),
            delimiter="\t",
        ))
    if any(len(row) != 3 or not all(row) for row in entries):
        raise ValueError("Each household item needs a label, Hindi name, and visual prompt")
    names, hindi, prompts = map(list, zip(*entries))
    if len(set(names)) != len(names):
        raise ValueError("Household labels must be unique")
    return names, hindi, prompts


def read_reference_photos(manifest, names):
    rows = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(rows, list) or not rows:
        raise ValueError("The reference photo manifest must contain a list of photos")

    references = defaultdict(list)
    for row in rows:
        label = row["label"]
        if label not in names:
            raise ValueError(f"Unknown household label: {label}")
        photo = manifest.parent / row["file"]
        if not photo.is_file():
            raise ValueError(f"Reference photo does not exist: {photo}")
        box = np.asarray(row["box"], dtype=np.float32)
        if (box.shape != (4,) or not np.all(np.isfinite(box))
                or not np.all((0 <= box) & (box <= 1))
                or not np.all(box[:2] < box[2:])):
            raise ValueError(f"Invalid normalized box for {label}: {row['box']}")
        references[label].append((photo, box))
    return references


def extract_reference_embeddings(checkpoint, references):
    from PIL import Image, ImageOps
    from ultralytics.models.yolo.yoloe import YOLOEVPSegPredictor

    source = YOLOE(checkpoint, verbose=False)
    predictor = YOLOEVPSegPredictor(overrides={
        "task": "segment", "mode": "predict", "imgsz": 640,
        "device": "cpu", "rect": False, "verbose": False, "batch": 1,
    })
    predictor.setup_model(model=source.model, verbose=False)

    embeddings = {}
    with torch.inference_mode():
        for label, photos in references.items():
            examples = []
            for path, box in photos:
                with Image.open(path) as image:
                    photo = ImageOps.exif_transpose(image).convert("RGB")
                width, height = photo.size
                pixels = (box * [width, height, width, height]).astype(np.float32)
                predictor.set_prompts({"bboxes": pixels[None], "cls": np.array([0])})
                embedding = predictor.get_vpe(np.asarray(photo)[..., ::-1].copy())
                examples.append(torch.nn.functional.normalize(embedding, dim=-1))
            embeddings[label] = torch.nn.functional.normalize(
                torch.stack(examples).mean(dim=0), dim=-1,
            )
    return embeddings


def fused_projections(checkpoint, names, prompts, visual_embeddings=None):
    detector = YOLOE("yoloe-26s.yaml", verbose=False).load(checkpoint)
    detector.model.eval()
    with torch.inference_mode():
        text = detector.model.get_text_pe(names + prompts, batch=32)
        short, specific = text.chunk(2, dim=1)
        embeddings = torch.nn.functional.normalize(short + specific, dim=-1)
        for label, example in (visual_embeddings or {}).items():
            index = names.index(label)
            current = embeddings[:, index:index + 1]
            current.copy_(torch.nn.functional.normalize(current + example, dim=-1))
        detector.set_classes(names, embeddings)
        head = detector.model.model[-1]
        head.fuse(embeddings)
    return [
        (
            branch[-1].weight.detach().cpu().numpy().reshape(len(names), 1, 1, -1),
            branch[-1].bias.detach().cpu().numpy().astype("<f4"),
        )
        for branch in head.cv3
    ]


def apply_reference_projections(names, projections, calibration):
    """Use the validated visual references for their corresponding classes."""
    for name, profile in calibration.items():
        index = names.index(name)
        for side, (weights, biases) in zip(HEAD_SIDES, projections, strict=True):
            row = profile["head"][str(side)]
            codes = np.frombuffer(base64.b64decode(row["filter"]), dtype=np.int8)
            weights[index, 0, 0] = codes.astype(np.float32) * np.float32(row["scale"])
            biases[index] = row["bias"]


def pack(model):
    builder = flatbuffers.Builder(1024 * 1024)
    builder.Finish(model.Pack(builder), file_identifier=b"TFL3")
    return bytes(builder.Output())


def write_model(output, data, files):
    stream = NamedTemporaryFile(dir=output.parent, prefix=f".{output.name}.", delete=False)
    temporary = Path(stream.name)
    try:
        with stream:
            stream.write(data)
        with ZipFile(temporary, "a") as archive:
            for filename, content in files.items():
                archive.writestr(filename, content)
        # The finished project asset needs the same read permissions as other models.
        temporary.chmod(0o644)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)


def update_reference_projections(base, output, names, projections, notes):
    """Update selected class rows in the existing model byte for byte."""
    if base.resolve() == output.resolve():
        raise ValueError("Write the candidate model to a new filename")

    raw = bytearray(base.read_bytes())
    with ZipFile(base) as archive:
        zip_start = min(entry.header_offset for entry in archive.infolist())
        files = {name: archive.read(name) for name in archive.namelist()}
    metadata = json.loads(files["metadata.json"])
    label_indices = {name: int(row) for row, name in metadata["names"].items()}
    rows = [label_indices[name] for name in names]
    label_count = len(label_indices)
    model = schema.Model.GetRootAsModel(raw, 0)
    graph = model.Subgraphs(0)
    if list(graph.Tensors(graph.Outputs(0)).ShapeAsNumpy()) != [1, 4 + label_count, ANCHORS]:
        raise ValueError("Expected Cue's one-output 640px household detector")

    updated = set()
    for index in range(graph.OperatorsLength()):
        operator = graph.Operators(index)
        if model.OperatorCodes(operator.OpcodeIndex()).BuiltinCode() != schema.BuiltinOperator.CONV_2D:
            continue
        input_index, filter_index, bias_index = operator.InputsAsNumpy()
        filters = graph.Tensors(int(filter_index))
        if list(filters.ShapeAsNumpy()) != [label_count, 1, 1, 128]:
            continue

        side = graph.Tensors(int(input_index)).Shape(1)
        weights, biases = projections[HEAD_SIDES.index(side)]
        buffer = model.Buffers(filters.Buffer())
        quant = filters.Quantization()
        if (buffer.Size() != label_count * 128 or not buffer.Offset()
                or quant.QuantizedDimension() != 0 or np.any(quant.ZeroPointAsNumpy() != 0)):
            raise ValueError("Expected per-label quantized filters")
        codes = np.frombuffer(raw, dtype=np.int8, count=buffer.Size(), offset=buffer.Offset())
        codes = codes.reshape(label_count, 128)
        scales = quant.ScaleAsNumpy()
        bias = model.Buffers(graph.Tensors(int(bias_index)).Buffer()).DataAsNumpy().view("<f4")
        if scales.shape != (label_count,) or bias.shape != (label_count,):
            raise ValueError("Expected one scale and bias per household label")

        weights = weights.reshape(len(rows), 128)
        new_scales = np.max(np.abs(weights), axis=1).astype("<f4") / 127
        if np.any(new_scales <= 0) or not np.all(np.isfinite(new_scales)) or not np.all(np.isfinite(biases)):
            raise ValueError("Photo projections must be finite and nonzero")
        codes[rows] = np.rint(weights / new_scales[:, None]).clip(-127, 127).astype(np.int8)
        scales[rows] = new_scales
        bias[rows] = biases
        updated.add(side)
    if updated != set(HEAD_SIDES):
        raise ValueError("Expected three quantized classification projections")

    metadata.setdefault("cue_calibration", {}).update(notes)
    files["metadata.json"] = json.dumps(metadata, separators=(",", ":")).encode()
    write_model(output, memoryview(raw)[:zip_start], files)


def extend_detector(base, output, names, prompts, projections, calibration=None):
    """Append real classifier channels without altering the calibrated rows."""
    if base.resolve() == output.resolve():
        raise ValueError("The expanded model needs a new filename")
    with ZipFile(base) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    metadata = json.loads(files["metadata.json"])
    original_names = [metadata["names"][str(index)] for index in range(len(metadata["names"]))]
    old_count = len(original_names)
    new_count = old_count + len(names)
    if set(original_names).intersection(names):
        raise ValueError("The base and household lists contain the same label")

    raw = base.read_bytes()
    model = schema.ModelT.InitFromObj(schema.Model.GetRootAsModel(raw, 0))
    graph, = model.subgraphs
    output_tensor = graph.tensors[graph.outputs[0]]
    if list(output_tensor.shape) != [1, 4 + old_count, ANCHORS]:
        raise ValueError("Expected Cue's one-output 640px YOLOE detection model")
    external = {
        index: raw[buffer.offset: buffer.offset + buffer.size]
        for index, buffer in enumerate(model.buffers)
        if buffer.offset
    }

    classifiers = {}
    reshapes = []
    for op in graph.operators:
        opcode = model.operatorCodes[op.opcodeIndex].builtinCode
        if opcode == schema.BuiltinOperator.CONV_2D:
            source, weights, bias = (graph.tensors[index] for index in op.inputs)
            if list(weights.shape) == [old_count, 1, 1, 128]:
                classifiers[int(source.shape[1])] = (weights, bias)
        if opcode == schema.BuiltinOperator.RESHAPE:
            result = graph.tensors[op.outputs[0]]
            if len(result.shape) == 3 and result.shape[1] == old_count:
                reshapes.append(model.buffers[graph.tensors[op.inputs[1]].buffer])
    if set(classifiers) != set(HEAD_SIDES) or len(reshapes) != len(HEAD_SIDES):
        raise ValueError("Expected three quantized classification projections and reshapes")

    for side, (floats, biases) in zip(HEAD_SIDES, projections, strict=True):
        weights, bias = classifiers[side]
        quant = weights.quantization
        existing = external[weights.buffer]
        bias_buffer = model.buffers[bias.buffer]
        if (quant.quantizedDimension != 0 or len(quant.scale) != old_count
                or np.any(quant.zeroPoint != 0) or len(existing) != old_count * 128
                or len(bias_buffer.data) != old_count * 4):
            raise ValueError("Expected per-label quantized filters and float biases")
        if (floats.shape != (len(names), 1, 1, 128) or biases.shape != (len(names),)
                or not np.isfinite(floats).all() or not np.isfinite(biases).all()):
            raise ValueError("Prompt projections do not match the base classifier")
        scales = np.max(np.abs(floats), axis=(1, 2, 3)).astype("<f4") / 127
        if np.any(scales <= 0):
            raise ValueError("A prompt projection has no signal")
        codes = np.rint(floats / scales[:, None, None, None]).clip(-127, 127).astype(np.int8)
        external[weights.buffer] = existing + codes.tobytes()
        quant.scale = np.concatenate((quant.scale, scales))
        quant.zeroPoint = np.concatenate((quant.zeroPoint, np.zeros(len(names), dtype=np.int64)))
        bias_buffer.data = np.concatenate((bias_buffer.data, biases.view(np.uint8)))

    for shape_buffer in reshapes:
        shape = shape_buffer.data.view("<i4").copy()
        if len(shape) != 3 or shape[1] != old_count:
            raise ValueError("Unexpected classifier reshape")
        shape[1] = new_count
        shape_buffer.data = shape.view(np.uint8)
    for tensor in graph.tensors:
        for field in ("shape", "shapeSignature"):
            shape = getattr(tensor, field)
            if shape is not None and old_count in shape:
                setattr(tensor, field, np.where(shape == old_count, new_count, shape).astype("<i4"))
    output_tensor.shape = np.array([1, new_count + 4, ANCHORS], dtype="<i4")

    for index, blob in external.items():
        model.buffers[index].size = len(blob)
    header_size = len(pack(model))
    position = header_size
    for index, blob in external.items():
        position = (position + 63) & ~63
        model.buffers[index].offset = position
        position += len(blob)
    header = pack(model)
    if len(header) != header_size:
        raise ValueError("Could not lay out the model's aligned weight buffers")

    metadata["names"] = dict(enumerate(original_names + names))
    metadata.setdefault("cue_added_classes", {}).update(zip(names, prompts, strict=True))
    if calibration:
        metadata["cue_calibration"] = {
            name: {key: value for key, value in row.items() if key != "head"}
            for name, row in calibration.items()
        }
    files["metadata.json"] = json.dumps(metadata, separators=(",", ":")).encode()
    data = bytearray(header)
    for index, blob in external.items():
        data.extend(bytes(model.buffers[index].offset - len(data)))
        data.extend(blob)
    write_model(output, data, files)


def write_hindi_labels(destination, names, hindi):
    lines = [
        "// Generated from tool/object_model/household_labels.tsv.",
        "const householdHindiObjectLabels = <String, String>{",
    ]
    for name, translation in zip(names, hindi, strict=True):
        lines.append(f"  '{name}': '{translation}',")
    lines.append("};\n")
    destination.write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--checkpoint", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--dart-labels", type=Path)
    parser.add_argument("--reference-photos", type=Path, help="Use boxed photos as visual prompts")
    args = parser.parse_args()

    torch.set_num_threads(4)
    names, hindi, prompts = read_labels()
    references = read_reference_photos(args.reference_photos, names) if args.reference_photos else {}
    notes = {
        label: {"method": "Text prompts blended with boxed reference photos",
                "reference_count": len(photos)}
        for label, photos in references.items()
    }
    visuals = extract_reference_embeddings(args.checkpoint, references) if references else {}

    with ZipFile(args.base) as archive:
        existing_labels = set(json.loads(archive.read("metadata.json"))["names"].values())
    if references and set(names) <= existing_labels:
        selected = [label for label in names if label in references]
        selected_prompts = [prompts[names.index(label)] for label in selected]
        projections = fused_projections(args.checkpoint, selected, selected_prompts, visuals)
        update_reference_projections(args.base, args.output, selected, projections, notes)
        print(f"Updated {len(selected)} photo-based labels in {args.output}")
    else:
        projections = fused_projections(args.checkpoint, names, prompts, visuals)
        calibration = json.loads(CALIBRATION.read_text(encoding="utf-8"))
        for label in references:
            calibration.pop(label, None)
        apply_reference_projections(names, projections, calibration)
        extend_detector(args.base, args.output, names, prompts, projections, calibration | notes)
        print(f"Fused {len(names)} household labels into {args.output}")
    if args.dart_labels is not None:
        write_hindi_labels(args.dart_labels, names, hindi)


if __name__ == "__main__":
    main()
