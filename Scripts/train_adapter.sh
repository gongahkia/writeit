#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLKIT_DIR="${ADAPTER_TOOLKIT_DIR:-}"
DATA_DIR="${DATA_DIR:-$HOME/Library/Application Support/cerberus/adapter-dataset}"
TRAIN_DATA="${TRAIN_DATA:-$DATA_DIR/train.jsonl}"
EVAL_DATA="${EVAL_DATA:-$DATA_DIR/eval.jsonl}"
CHECKPOINT_DIR="${CHECKPOINT_DIR:-$ROOT_DIR/.dist/adapter-training/checkpoints}"
DRAFT_CHECKPOINT_DIR="${DRAFT_CHECKPOINT_DIR:-$ROOT_DIR/.dist/adapter-training/draft-checkpoints}"
EXPORT_DIR="${EXPORT_DIR:-$ROOT_DIR/.dist/adapter-training/exports}"
ADAPTER_NAME="${ADAPTER_NAME:-cerberus_adapter}"
ADAPTER_CHECKPOINT="${ADAPTER_CHECKPOINT:-$CHECKPOINT_DIR/adapter-final.pt}"
DRAFT_CHECKPOINT="${DRAFT_CHECKPOINT:-$DRAFT_CHECKPOINT_DIR/draft-model-final.pt}"
EPOCHS="${EPOCHS:-5}"
LEARNING_RATE="${LEARNING_RATE:-1e-3}"
BATCH_SIZE="${BATCH_SIZE:-4}"
PYTHON="${PYTHON:-python3}"
TRAIN_DRAFT="${TRAIN_DRAFT:-0}"
EXPORT_ADAPTER="${EXPORT_ADAPTER:-1}"

usage() {
  print "usage: ADAPTER_TOOLKIT_DIR=/path/to/toolkit Scripts/train_adapter.sh"
  print ""
  print "env:"
  print "  DATA_DIR=$DATA_DIR"
  print "  TRAIN_DATA=$TRAIN_DATA"
  print "  EVAL_DATA=$EVAL_DATA"
  print "  CHECKPOINT_DIR=$CHECKPOINT_DIR"
  print "  EXPORT_DIR=$EXPORT_DIR"
  print "  ADAPTER_NAME=$ADAPTER_NAME"
  print "  EPOCHS=$EPOCHS"
  print "  LEARNING_RATE=$LEARNING_RATE"
  print "  BATCH_SIZE=$BATCH_SIZE"
  print "  TRAIN_DRAFT=0|1"
  print "  EXPORT_ADAPTER=0|1"
  print "  PYTHON=$PYTHON"
}

fail() {
  print -u2 "adapter training failed: $1"
  exit "${2:-70}"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

[[ -n "$TOOLKIT_DIR" ]] || fail "set ADAPTER_TOOLKIT_DIR to Apple's Foundation Models adapter training toolkit." 64
[[ -d "$TOOLKIT_DIR" ]] || fail "ADAPTER_TOOLKIT_DIR does not exist: $TOOLKIT_DIR" 66
[[ -f "$TOOLKIT_DIR/examples/train_adapter.py" ]] || fail "toolkit is missing examples/train_adapter.py." 66
[[ -f "$TOOLKIT_DIR/export/export_fmadapter.py" ]] || fail "toolkit is missing export/export_fmadapter.py." 66
[[ -f "$TRAIN_DATA" ]] || fail "train data not found: $TRAIN_DATA" 66
[[ -f "$EVAL_DATA" ]] || fail "eval data not found: $EVAL_DATA" 66
command -v "$PYTHON" >/dev/null 2>&1 || fail "$PYTHON is not on PATH." 69

mkdir -p "$CHECKPOINT_DIR" "$EXPORT_DIR"

cd "$TOOLKIT_DIR"

"$PYTHON" -m examples.train_adapter \
  --train-data "$TRAIN_DATA" \
  --eval-data "$EVAL_DATA" \
  --epochs "$EPOCHS" \
  --learning-rate "$LEARNING_RATE" \
  --batch-size "$BATCH_SIZE" \
  --checkpoint-dir "$CHECKPOINT_DIR"

[[ -f "$ADAPTER_CHECKPOINT" ]] || fail "adapter checkpoint not found after training: $ADAPTER_CHECKPOINT" 66

draft_args=()
if [[ "$TRAIN_DRAFT" == "1" ]]; then
  [[ -f "$TOOLKIT_DIR/examples/train_draft_model.py" ]] || fail "toolkit is missing examples/train_draft_model.py." 66
  mkdir -p "$DRAFT_CHECKPOINT_DIR"
  "$PYTHON" -m examples.train_draft_model \
    --checkpoint "$ADAPTER_CHECKPOINT" \
    --train-data "$TRAIN_DATA" \
    --eval-data "$EVAL_DATA" \
    --epochs "$EPOCHS" \
    --learning-rate "$LEARNING_RATE" \
    --batch-size "$BATCH_SIZE" \
    --checkpoint-dir "$DRAFT_CHECKPOINT_DIR"
  [[ -f "$DRAFT_CHECKPOINT" ]] || fail "draft checkpoint not found after training: $DRAFT_CHECKPOINT" 66
  draft_args+=(--draft-checkpoint "$DRAFT_CHECKPOINT")
fi

if [[ "$EXPORT_ADAPTER" == "1" ]]; then
  "$PYTHON" -m export.export_fmadapter \
    --adapter-name "$ADAPTER_NAME" \
    --checkpoint "$ADAPTER_CHECKPOINT" \
    "${draft_args[@]}" \
    --output-dir "$EXPORT_DIR"
  print "$EXPORT_DIR/$ADAPTER_NAME.fmadapter"
else
  print "$ADAPTER_CHECKPOINT"
fi
