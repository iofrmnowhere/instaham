"""INSTAHAM model export toolchain.

Converts the (non-final) research checkpoints under ML/ into mobile ONNX artifacts plus a
manifest that the native runtime (packages/instaham_ml_ffi) loads. Never ships in the app;
never modifies the frozen reference .py files.
"""
