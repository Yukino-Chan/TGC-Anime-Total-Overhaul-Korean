"""Legacy release storage is retired. Use publish_latest.py (GHCR protocol 2)."""
def publish(*args, **kwargs):
    raise RuntimeError("Legacy publisher retired; use publish_latest.py")
