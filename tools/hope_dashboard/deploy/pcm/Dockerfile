FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy dashboard source
COPY app.py data_loader.py ./
COPY assets/ assets/
COPY data/ data/

# Copy bundled sample case data
COPY ModelCases/ ModelCases/

# Environment variables for Hugging Face Spaces
ENV HOPE_MODELCASES_PATH=/app/ModelCases
ENV DASH_HOST=0.0.0.0
ENV DASH_PORT=7860
ENV DASH_DEBUG=false

EXPOSE 7860

CMD ["python", "app.py"]
