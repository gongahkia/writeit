#!/usr/bin/env python3
import argparse
import json
import pathlib
import shutil
import subprocess
import tempfile

import coremltools as ct
import torch
from transformers import TrOCRProcessor, VisionEncoderDecoderModel


def parse_arguments():
  parser = argparse.ArgumentParser()
  parser.add_argument("--model", default="microsoft/trocr-small-handwritten")
  parser.add_argument("--output", required=True, type=pathlib.Path)
  parser.add_argument("--max-tokens", default=64, type=int)
  return parser.parse_args()


class Encoder(torch.nn.Module):
  def __init__(self, model):
    super().__init__()
    self.model = model

  def forward(self, pixel_values):
    return self.model(pixel_values=pixel_values).last_hidden_state


class Decoder(torch.nn.Module):
  def __init__(self, model):
    super().__init__()
    self.model = model

  def forward(self, input_ids, encoder_hidden_states):
    return self.model(
      input_ids=input_ids,
      encoder_hidden_states=encoder_hidden_states,
      use_cache=False,
    ).logits


def convert_model(module, inputs, package, output, name):
  traced = torch.jit.trace(module, inputs, strict=False)
  model = ct.convert(
    traced,
    inputs=package,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.macOS15,
  )
  package_path = output / f"{name}.mlpackage"
  model.save(package_path)
  compiled = output / f"{name}.mlmodelc"
  subprocess.run(
    ["xcrun", "coremlcompiler", "compile", str(package_path), str(output)], check=True
  )
  if not compiled.is_dir():
    raise RuntimeError(f"coremlcompiler did not create {compiled}")
  shutil.rmtree(package_path)


def write_bundle(processor, model, output, max_tokens):
  vocabulary = processor.tokenizer.get_vocab()
  tokenizer = {
    "vocabulary": vocabulary,
    "bos_token_id": model.config.decoder_start_token_id,
    "eos_token_id": model.config.eos_token_id,
    "pad_token_id": model.config.pad_token_id,
  }
  runtime = {
    "schema_version": 1,
    "encoder_model_file": "encoder.mlmodelc",
    "decoder_model_file": "decoder.mlmodelc",
    "encoder_input_name": "pixel_values",
    "encoder_output_name": "last_hidden_state",
    "decoder_encoder_input_name": "encoder_hidden_states",
    "decoder_token_input_name": "input_ids",
    "decoder_logits_output_name": "logits",
    "image_width": processor.image_processor.size["width"],
    "image_height": processor.image_processor.size["height"],
    "decoder_token_count": max_tokens,
    "maximum_generated_tokens": max_tokens,
  }
  (output / "writeit-trocr-tokenizer.json").write_text(json.dumps(tokenizer, sort_keys=True))
  (output / "writeit-trocr-runtime.json").write_text(json.dumps(runtime, sort_keys=True))


def main():
  args = parse_arguments()
  if args.max_tokens < 1 or args.max_tokens > 256:
    raise ValueError("--max-tokens must be between 1 and 256")
  output = args.output.resolve()
  if output.exists():
    raise FileExistsError(output)
  processor = TrOCRProcessor.from_pretrained(args.model)
  model = VisionEncoderDecoderModel.from_pretrained(args.model).eval()
  output.mkdir(parents=True)
  try:
    height = processor.image_processor.size["height"]
    width = processor.image_processor.size["width"]
    pixel_values = torch.zeros((1, 3, height, width), dtype=torch.float32)
    encoder = Encoder(model.encoder).eval()
    with torch.no_grad():
      hidden_states = encoder(pixel_values)
    input_ids = torch.full(
      (1, args.max_tokens), model.config.pad_token_id, dtype=torch.int64
    )
    input_ids[0, 0] = model.config.decoder_start_token_id
    decoder = Decoder(model.decoder).eval()
    convert_model(
      encoder,
      (pixel_values,),
      [ct.TensorType(name="pixel_values", shape=pixel_values.shape, dtype=float)],
      output,
      "encoder",
    )
    convert_model(
      decoder,
      (input_ids, hidden_states),
      [
        ct.TensorType(name="input_ids", shape=input_ids.shape, dtype=int),
        ct.TensorType(name="encoder_hidden_states", shape=hidden_states.shape, dtype=float),
      ],
      output,
      "decoder",
    )
    write_bundle(processor, model, output, args.max_tokens)
  except Exception:
    shutil.rmtree(output, ignore_errors=True)
    raise


if __name__ == "__main__":
  main()
