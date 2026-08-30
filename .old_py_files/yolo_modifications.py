from __future__ import annotations

"""INSTAHAM YOLO neck modification: LDConv + ACmix.

Architecture basis:
- Chen et al. (2025) place LDConv in the YOLO11 neck and ACmix before the
  second LDConv in their architecture diagram.
- INSTAHAM retains the selected YOLO backbone. Only the LDConv/ACmix neck idea is adapted.

Implementation basis:
- LDConv follows the public reference implementation from CV-ZhangXin/LDConv.
- ACmix follows the public reference implementation from LeapLabTHU/ACmix,
  with device-safe positional encoding.
"""

import math
from dataclasses import dataclass, asdict
from typing import Any

import torch
import torch.nn as nn


@dataclass(frozen=True)
class NeckModificationConfig:
    ldconv_num_param: int = 5
    acmix_kernel_att: int = 7
    acmix_heads: int = 4
    acmix_kernel_conv: int = 3

    def to_dict(self) -> dict[str, int]:
        return asdict(self)


def _copy_ultralytics_metadata(old: nn.Module, new: nn.Module) -> nn.Module:
    """Preserve graph metadata attached by Ultralytics parse_model()."""
    for name in ("i", "f", "type", "np"):
        if hasattr(old, name):
            setattr(new, name, getattr(old, name))
    new.type = new.__class__.__name__
    new.np = sum(p.numel() for p in new.parameters())
    return new


class LDConv(nn.Module):
    """Linear Deformable Convolution adapted from the authors' reference code."""

    def __init__(self, inc: int, outc: int, num_param: int, stride: int = 1, bias: bool | None = None):
        super().__init__()
        if num_param < 1:
            raise ValueError("LDConv num_param must be >= 1")
        self.num_param = int(num_param)
        self.stride = int(stride)
        self.conv = nn.Sequential(
            nn.Conv2d(inc, outc, kernel_size=(self.num_param, 1), stride=(self.num_param, 1), bias=bias),
            nn.BatchNorm2d(outc),
            nn.SiLU(),
        )
        self.p_conv = nn.Conv2d(inc, 2 * self.num_param, kernel_size=3, padding=1, stride=self.stride)
        nn.init.constant_(self.p_conv.weight, 0.0)
        if self.p_conv.bias is not None:
            nn.init.constant_(self.p_conv.bias, 0.0)
        self.register_buffer("p_n", self._get_p_n(self.num_param), persistent=True)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        offset = self.p_conv(x)
        n = offset.size(1) // 2
        p = self._get_p(offset)
        p = p.contiguous().permute(0, 2, 3, 1)

        q_lt = p.detach().floor()
        q_rb = q_lt + 1
        q_lt = torch.cat(
            [
                torch.clamp(q_lt[..., :n], 0, x.size(2) - 1),
                torch.clamp(q_lt[..., n:], 0, x.size(3) - 1),
            ],
            dim=-1,
        ).long()
        q_rb = torch.cat(
            [
                torch.clamp(q_rb[..., :n], 0, x.size(2) - 1),
                torch.clamp(q_rb[..., n:], 0, x.size(3) - 1),
            ],
            dim=-1,
        ).long()
        q_lb = torch.cat([q_lt[..., :n], q_rb[..., n:]], dim=-1)
        q_rt = torch.cat([q_rb[..., :n], q_lt[..., n:]], dim=-1)

        p = torch.cat(
            [
                torch.clamp(p[..., :n], 0, x.size(2) - 1),
                torch.clamp(p[..., n:], 0, x.size(3) - 1),
            ],
            dim=-1,
        )

        g_lt = (1 + (q_lt[..., :n].type_as(p) - p[..., :n])) * (1 + (q_lt[..., n:].type_as(p) - p[..., n:]))
        g_rb = (1 - (q_rb[..., :n].type_as(p) - p[..., :n])) * (1 - (q_rb[..., n:].type_as(p) - p[..., n:]))
        g_lb = (1 + (q_lb[..., :n].type_as(p) - p[..., :n])) * (1 - (q_lb[..., n:].type_as(p) - p[..., n:]))
        g_rt = (1 - (q_rt[..., :n].type_as(p) - p[..., :n])) * (1 + (q_rt[..., n:].type_as(p) - p[..., n:]))

        x_q_lt = self._get_x_q(x, q_lt, n)
        x_q_rb = self._get_x_q(x, q_rb, n)
        x_q_lb = self._get_x_q(x, q_lb, n)
        x_q_rt = self._get_x_q(x, q_rt, n)
        x_offset = (
            g_lt.unsqueeze(1) * x_q_lt
            + g_rb.unsqueeze(1) * x_q_rb
            + g_lb.unsqueeze(1) * x_q_lb
            + g_rt.unsqueeze(1) * x_q_rt
        )
        x_offset = self._reshape_x_offset(x_offset)
        return self.conv(x_offset)

    def _get_p_n(self, n: int) -> torch.Tensor:
        base_int = max(1, round(math.sqrt(n)))
        row_number = n // base_int
        mod_number = n % base_int
        xs, ys = torch.meshgrid(
            torch.arange(0, row_number), torch.arange(0, base_int), indexing="ij"
        )
        p_n_x, p_n_y = xs.flatten(), ys.flatten()
        if mod_number > 0:
            mx, my = torch.meshgrid(
                torch.arange(row_number, row_number + 1), torch.arange(0, mod_number), indexing="ij"
            )
            p_n_x = torch.cat((p_n_x, mx.flatten()))
            p_n_y = torch.cat((p_n_y, my.flatten()))
        p_n = torch.cat([p_n_x, p_n_y], 0).view(1, 2 * n, 1, 1).float()
        return p_n

    def _get_p_0(self, h: int, w: int, n: int, device: torch.device, dtype: torch.dtype) -> torch.Tensor:
        xs, ys = torch.meshgrid(
            torch.arange(0, h * self.stride, self.stride, device=device, dtype=dtype),
            torch.arange(0, w * self.stride, self.stride, device=device, dtype=dtype),
            indexing="ij",
        )
        p_0_x = xs.flatten().view(1, 1, h, w).repeat(1, n, 1, 1)
        p_0_y = ys.flatten().view(1, 1, h, w).repeat(1, n, 1, 1)
        return torch.cat([p_0_x, p_0_y], 1)

    def _get_p(self, offset: torch.Tensor) -> torch.Tensor:
        n, h, w = offset.size(1) // 2, offset.size(2), offset.size(3)
        p_0 = self._get_p_0(h, w, n, offset.device, offset.dtype)
        return p_0 + self.p_n.to(device=offset.device, dtype=offset.dtype) + offset

    @staticmethod
    def _get_x_q(x: torch.Tensor, q: torch.Tensor, n: int) -> torch.Tensor:
        b, h, w, _ = q.size()
        padded_w = x.size(3)
        c = x.size(1)
        flat = x.contiguous().view(b, c, -1)
        index = q[..., :n] * padded_w + q[..., n:]
        index = index.contiguous().unsqueeze(1).expand(-1, c, -1, -1, -1).contiguous().view(b, c, -1)
        return flat.gather(dim=-1, index=index).contiguous().view(b, c, h, w, n)

    @staticmethod
    def _reshape_x_offset(x_offset: torch.Tensor) -> torch.Tensor:
        b, c, h, w, n = x_offset.size()
        # Same row-stacking operation as the reference implementation, without einops.
        return x_offset.permute(0, 1, 2, 4, 3).contiguous().view(b, c, h * n, w)


class ACmix(nn.Module):
    """ACmix adapted from the authors' public PyTorch implementation."""

    def __init__(
        self,
        in_planes: int,
        out_planes: int,
        kernel_att: int = 7,
        head: int = 4,
        kernel_conv: int = 3,
        stride: int = 1,
        dilation: int = 1,
    ):
        super().__init__()
        if out_planes % head != 0:
            raise ValueError(f"ACmix out_planes={out_planes} must be divisible by head={head}")
        self.in_planes = in_planes
        self.out_planes = out_planes
        self.head = head
        self.kernel_att = kernel_att
        self.kernel_conv = kernel_conv
        self.stride = stride
        self.dilation = dilation
        self.rate1 = nn.Parameter(torch.tensor(0.5))
        self.rate2 = nn.Parameter(torch.tensor(0.5))
        self.head_dim = out_planes // head
        self.conv1 = nn.Conv2d(in_planes, out_planes, kernel_size=1)
        self.conv2 = nn.Conv2d(in_planes, out_planes, kernel_size=1)
        self.conv3 = nn.Conv2d(in_planes, out_planes, kernel_size=1)
        self.conv_p = nn.Conv2d(2, self.head_dim, kernel_size=1)
        self.padding_att = (dilation * (kernel_att - 1) + 1) // 2
        self.pad_att = nn.ReflectionPad2d(self.padding_att)
        self.unfold = nn.Unfold(kernel_size=kernel_att, padding=0, stride=stride)
        self.softmax = nn.Softmax(dim=1)
        self.fc = nn.Conv2d(3 * head, kernel_conv * kernel_conv, kernel_size=1, bias=False)
        self.dep_conv = nn.Conv2d(
            kernel_conv * kernel_conv * self.head_dim,
            out_planes,
            kernel_size=kernel_conv,
            bias=True,
            groups=self.head_dim,
            padding=kernel_conv // 2,
            stride=stride,
        )
        self.reset_parameters()

    def reset_parameters(self) -> None:
        with torch.no_grad():
            self.rate1.fill_(0.5)
            self.rate2.fill_(0.5)
            kernel = torch.zeros(self.kernel_conv * self.kernel_conv, self.kernel_conv, self.kernel_conv)
            for i in range(self.kernel_conv * self.kernel_conv):
                kernel[i, i // self.kernel_conv, i % self.kernel_conv] = 1.0
            kernel = kernel.repeat(self.out_planes, 1, 1, 1)
            self.dep_conv.weight.copy_(kernel)
            if self.dep_conv.bias is not None:
                self.dep_conv.bias.zero_()

    @staticmethod
    def _position(h: int, w: int, device: torch.device, dtype: torch.dtype) -> torch.Tensor:
        loc_w = torch.linspace(-1.0, 1.0, w, device=device, dtype=dtype).unsqueeze(0).repeat(h, 1)
        loc_h = torch.linspace(-1.0, 1.0, h, device=device, dtype=dtype).unsqueeze(1).repeat(1, w)
        return torch.cat([loc_w.unsqueeze(0), loc_h.unsqueeze(0)], 0).unsqueeze(0)

    @staticmethod
    def _stride(x: torch.Tensor, stride: int) -> torch.Tensor:
        return x[:, :, ::stride, ::stride]

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        q, k, v = self.conv1(x), self.conv2(x), self.conv3(x)
        scaling = float(self.head_dim) ** -0.5
        b, _, h, w = q.shape
        # Unfold determines the exact output dimensions, including odd inputs.
        pe = self.conv_p(self._position(h, w, x.device, x.dtype))
        q_att = q.view(b * self.head, self.head_dim, h, w) * scaling
        k_att = k.view(b * self.head, self.head_dim, h, w)
        v_att = v.view(b * self.head, self.head_dim, h, w)
        if self.stride > 1:
            q_att = self._stride(q_att, self.stride)
            q_pe = self._stride(pe, self.stride)
        else:
            q_pe = pe

        unfold_k_raw = self.unfold(self.pad_att(k_att))
        h_out, w_out = q_att.shape[-2:]
        expected = h_out * w_out
        if unfold_k_raw.shape[-1] != expected:
            # Match PyTorch Unfold for rare odd-sized feature maps.
            h_out = int(math.sqrt(unfold_k_raw.shape[-1]))
            while h_out > 1 and unfold_k_raw.shape[-1] % h_out:
                h_out -= 1
            w_out = unfold_k_raw.shape[-1] // h_out
            q_att = q_att[..., :h_out, :w_out]
            q_pe = q_pe[..., :h_out, :w_out]

        unfold_k = unfold_k_raw.view(b * self.head, self.head_dim, self.kernel_att ** 2, h_out, w_out)
        unfold_rpe = self.unfold(self.pad_att(pe)).view(1, self.head_dim, self.kernel_att ** 2, h_out, w_out)
        att = (q_att.unsqueeze(2) * (unfold_k + q_pe.unsqueeze(2) - unfold_rpe)).sum(1)
        att = self.softmax(att)
        out_att = self.unfold(self.pad_att(v_att)).view(
            b * self.head, self.head_dim, self.kernel_att ** 2, h_out, w_out
        )
        out_att = (att.unsqueeze(1) * out_att).sum(2).view(b, self.out_planes, h_out, w_out)

        f_all = self.fc(
            torch.cat(
                [
                    q.view(b, self.head, self.head_dim, h * w),
                    k.view(b, self.head, self.head_dim, h * w),
                    v.view(b, self.head, self.head_dim, h * w),
                ],
                1,
            )
        )
        f_conv = f_all.permute(0, 2, 1, 3).reshape(b, -1, h, w)
        out_conv = self.dep_conv(f_conv)
        if out_conv.shape[-2:] != out_att.shape[-2:]:
            out_conv = out_conv[..., : out_att.shape[-2], : out_att.shape[-1]]
        return self.rate1 * out_att + self.rate2 * out_conv


class ACmixLDConvDownsample(nn.Module):
    """ACmix followed by LDConv, matching the relative placement in Chen et al."""

    def __init__(self, inc: int, outc: int, cfg: NeckModificationConfig):
        super().__init__()
        head = _compatible_head_count(inc, cfg.acmix_heads)
        self.acmix = ACmix(
            inc,
            inc,
            kernel_att=cfg.acmix_kernel_att,
            head=head,
            kernel_conv=cfg.acmix_kernel_conv,
            stride=1,
        )
        self.ldconv = LDConv(inc, outc, num_param=cfg.ldconv_num_param, stride=2, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.ldconv(self.acmix(x))


def _compatible_head_count(channels: int, requested: int) -> int:
    for heads in range(min(int(requested), int(channels)), 0, -1):
        if channels % heads == 0:
            return heads
    return 1


def _ultralytics_conv_spec(module: nn.Module) -> tuple[int, int, tuple[int, int]] | None:
    conv = getattr(module, "conv", None)
    if not isinstance(conv, nn.Conv2d):
        return None
    stride = tuple(int(v) for v in conv.stride)
    return int(conv.in_channels), int(conv.out_channels), stride


def find_neck_downsample_indices(segmentation_model: nn.Module) -> list[int]:
    """Return the two final top-level stride-2 Conv blocks before the segmentation head.

    YOLO11-seg and YOLO26-seg currently expose two such PAN/neck downsampling Conv
    blocks. The guard intentionally fails if a future Ultralytics graph no longer matches
    that structure instead of silently modifying the wrong layers.
    """
    graph = getattr(segmentation_model, "model", None)
    if graph is None:
        raise TypeError("Expected an Ultralytics SegmentationModel with a .model graph")
    candidates: list[int] = []
    for idx, module in enumerate(graph):
        spec = _ultralytics_conv_spec(module)
        if spec is None:
            continue
        _, _, stride = spec
        if stride == (2, 2):
            candidates.append(idx)
    if len(candidates) < 2:
        raise RuntimeError(f"Could not find two stride-2 Conv blocks in model graph: {candidates}")
    target = candidates[-2:]
    # Current official YOLO11/YOLO26 segment graphs use these as neck/PAN downsampling.
    if target[1] - target[0] < 2:
        raise RuntimeError(f"Unexpected neck downsampling layout: {target}")
    return target


def apply_ldconv_acmix(
    segmentation_model: nn.Module,
    cfg: NeckModificationConfig | dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Replace two neck downsampling Conv blocks; insert ACmix before the second LDConv."""
    if cfg is None:
        cfg = NeckModificationConfig()
    elif isinstance(cfg, dict):
        cfg = NeckModificationConfig(**cfg)
    graph = segmentation_model.model
    first_idx, second_idx = find_neck_downsample_indices(segmentation_model)
    first_old, second_old = graph[first_idx], graph[second_idx]
    first_spec, second_spec = _ultralytics_conv_spec(first_old), _ultralytics_conv_spec(second_old)
    if first_spec is None or second_spec is None:
        raise RuntimeError("Target neck layers are not standard Ultralytics Conv modules")
    c1a, c2a, stride_a = first_spec
    c1b, c2b, stride_b = second_spec
    if stride_a != (2, 2) or stride_b != (2, 2):
        raise RuntimeError("Target neck Conv modules must both use stride=2")

    first_new = _copy_ultralytics_metadata(
        first_old,
        LDConv(c1a, c2a, num_param=cfg.ldconv_num_param, stride=2, bias=False),
    )
    second_new = _copy_ultralytics_metadata(
        second_old,
        ACmixLDConvDownsample(c1b, c2b, cfg),
    )
    graph[first_idx] = first_new
    graph[second_idx] = second_new
    return {
        "first_neck_index": first_idx,
        "second_neck_index": second_idx,
        "first_channels": [c1a, c2a],
        "second_channels": [c1b, c2b],
        "config": cfg.to_dict(),
        "description": "LDConv replaces both neck stride-2 Conv blocks; ACmix is immediately before the second LDConv.",
    }


def make_modified_segmentation_trainer(cfg: NeckModificationConfig | dict[str, Any] | None = None):
    """Build an Ultralytics SegmentationTrainer subclass that applies the modification before loading weights.

    Applying the structural change before model.load(weights) is important for both:
    - fresh runs: all unchanged pretrained weights transfer, new modules initialize normally;
    - resume runs: LDConv/ACmix checkpoint tensors load back into the same modified graph.
    """
    from ultralytics.models.yolo.segment import SegmentationTrainer
    from ultralytics.nn.tasks import SegmentationModel
    from ultralytics.utils import RANK

    if cfg is None:
        resolved_cfg = NeckModificationConfig()
    elif isinstance(cfg, dict):
        resolved_cfg = NeckModificationConfig(**cfg)
    else:
        resolved_cfg = cfg

    class ModifiedSegmentationTrainer(SegmentationTrainer):
        instaham_modification_config = resolved_cfg.to_dict()

        def get_model(self, cfg=None, weights=None, verbose=True):
            channels = int(self.data.get("channels", 3))
            model = SegmentationModel(
                cfg,
                nc=self.data["nc"],
                ch=channels,
                verbose=bool(verbose and RANK == -1),
            )
            model.instaham_neck_modification = apply_ldconv_acmix(model, resolved_cfg)
            if weights:
                model.load(weights)
            return model

    ModifiedSegmentationTrainer.__name__ = "INSTAHAMModifiedSegmentationTrainer"
    return ModifiedSegmentationTrainer


def describe_modified_model(model: nn.Module) -> dict[str, Any]:
    """Return a serializable description for run manifests/checks."""
    info = getattr(model, "instaham_neck_modification", None)
    if info is not None:
        return dict(info)
    return {
        "indices": find_neck_downsample_indices(model),
        "modified": any(isinstance(m, (LDConv, ACmixLDConvDownsample)) for m in model.model),
    }


def register_checkpoint_safe_globals() -> None:
    """Register custom modules for PyTorch safe checkpoint loading when supported."""
    add_safe = getattr(torch.serialization, "add_safe_globals", None)
    if add_safe is not None:
        try:
            add_safe([LDConv, ACmix, ACmixLDConvDownsample, NeckModificationConfig])
        except Exception:
            pass
