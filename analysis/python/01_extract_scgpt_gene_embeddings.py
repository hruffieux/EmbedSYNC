"""Extract static scGPT gene-token embeddings for the frozen gene panel.

This is the only part of EmbedSYNC that is not R. It exists because the scGPT
checkpoint is a PyTorch state_dict, so reading it needs torch. It runs once, and
everything downstream (similarity, graph, communities, modelling) is done in R
from the cached CSV this writes.

The model is used only as a lookup table. Nothing is fine-tuned, no expression
data are passed through the network, and the bulk longitudinal samples are never
embedded as cells. The gene representations here are those learnt during
pretraining and are independent of the GSE194378 data.

The scGPT GeneEncoder is an embedding lookup followed by a LayerNorm, and the
official gene-embedding workflow obtains representations by calling that encoder
rather than by reading the embedding matrix directly. The LayerNorm is therefore
applied here too. It is not a cosmetic choice: its learned elementwise scale and
shift change the direction of each gene vector, and the groups are built from
cosine similarity, which depends on direction.

Usage, from the repository root:
    .venv/bin/python analysis/python/01_extract_scgpt_gene_embeddings.py

Runtime: a few seconds once the checkpoint is present locally.
"""

import json
import pathlib
import platform
import sys

import torch
import torch.nn.functional as F

ROOT = pathlib.Path(__file__).resolve().parents[2]
EXTERNAL = ROOT / "analysis" / "data" / "external"
PANEL_CSV = ROOT / "analysis" / "metadata" / "02_gene_panel.csv"
OUT_DIR = ROOT / "analysis" / "objects" / "embeddings"

CHECKPOINT = EXTERNAL / "scgpt_human_best_model.pt"
VOCAB = EXTERNAL / "scgpt_human_vocab.json"
ARGS = EXTERNAL / "scgpt_human_args.json"

EMBEDDING_KEY = "encoder.embedding.weight"
NORM_WEIGHT_KEY = "encoder.enc_norm.weight"
NORM_BIAS_KEY = "encoder.enc_norm.bias"
LAYER_NORM_EPS = 1e-5  # torch.nn.LayerNorm default


def read_panel(path):
    """Read the frozen panel, returning (row_id, scgpt_symbol) in panel order."""
    with open(path) as handle:
        header = [h.strip().strip('"') for h in handle.readline().rstrip("\n").split(",")]
        i_row = header.index("row_id")
        i_sym = header.index("scgpt_symbol")
        rows = []
        for line in handle:
            fields = [f.strip().strip('"') for f in line.rstrip("\n").split(",")]
            rows.append((fields[i_row], fields[i_sym]))
    return rows


def main():
    for path in (CHECKPOINT, VOCAB, ARGS, PANEL_CSV):
        if not path.exists():
            sys.exit(f"Missing required file: {path}")

    vocab = json.load(open(VOCAB))
    args = json.load(open(ARGS))
    embsize = args["embsize"]

    panel = read_panel(PANEL_CSV)
    missing = [sym for _, sym in panel if sym not in vocab]
    if missing:
        sys.exit(f"{len(missing)} panel genes absent from the scGPT vocabulary, "
                 f"e.g. {missing[:5]}. The panel should already guarantee coverage.")

    state = torch.load(CHECKPOINT, map_location="cpu", weights_only=True)

    weight = state[EMBEDDING_KEY]
    # Guard against a checkpoint whose shape does not match its own config, which
    # would mean the vocabulary and the embedding table disagree.
    if tuple(weight.shape) != (len(vocab), embsize):
        sys.exit(f"{EMBEDDING_KEY} has shape {tuple(weight.shape)}, expected "
                 f"{(len(vocab), embsize)} from the vocabulary and args.json.")

    index = torch.tensor([vocab[sym] for _, sym in panel], dtype=torch.long)
    emb = weight[index]

    # LayerNorm acts on each gene vector independently, so applying it after
    # subsetting gives the same result as applying it to the whole table.
    emb = F.layer_norm(
        emb, (embsize,),
        weight=state[NORM_WEIGHT_KEY], bias=state[NORM_BIAS_KEY],
        eps=LAYER_NORM_EPS,
    )

    if not torch.isfinite(emb).all():
        sys.exit("Extracted embeddings contain non-finite values.")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_csv = OUT_DIR / "03_scgpt_panel_embeddings.csv"
    with open(out_csv, "w") as handle:
        handle.write("row_id," + ",".join(f"dim{i + 1}" for i in range(embsize)) + "\n")
        for (row_id, _), vec in zip(panel, emb.tolist()):
            handle.write(row_id + "," + ",".join(f"{v:.6g}" for v in vec) + "\n")

    provenance = {
        "checkpoint": "wanglab/scGPT-human (whole-human, CellxGene census May 2023)",
        "checkpoint_file": CHECKPOINT.name,
        "embedding_key": EMBEDDING_KEY,
        "layer_norm_applied": True,
        "embedding_dim": embsize,
        "vocab_size": len(vocab),
        "panel_genes": len(panel),
        "torch_version": torch.__version__,
        "python_version": platform.python_version(),
    }
    with open(OUT_DIR / "03_scgpt_embedding_provenance.json", "w") as handle:
        json.dump(provenance, handle, indent=2)

    print(f"Extracted {emb.shape[0]} x {emb.shape[1]} gene embeddings")
    print(f"  value range: [{emb.min():.3f}, {emb.max():.3f}]")
    print(f"  written to:  {out_csv.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
