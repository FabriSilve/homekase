FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN echo "app ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/app

WORKDIR /app

COPY pyproject.toml .
RUN pip install --no-cache-dir $(python3 -c "\
import tomllib; \
cfg = tomllib.load(open('pyproject.toml','rb')); \
print(' '.join(cfg['project'].get('dependencies', [])))")

COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
