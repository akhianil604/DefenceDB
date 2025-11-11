import os
from typing import Optional, Mapping, Any

# Import the real factory from app.py
from .app import create_app as _create_app

def create_app(config: Optional[Mapping[str, Any]] = None):
    """
    Flask application factory.

    - Pulls SECRET_KEY from env if present
    - Accepts an optional config mapping to override defaults
    - Returns a configured Flask app
    """
    app = _create_app()

    # Default secret key from env (if provided)
    env_secret = os.environ.get('SECRET_KEY')
    if env_secret:
        app.config['SECRET_KEY'] = env_secret

    # Allow caller overrides
    if config:
        app.config.update(config)

    return app

# Expose a default app instance for WSGI servers (gunicorn/uwsgi) and `flask run`
app = create_app()

__all__ = ["create_app", "app"]

