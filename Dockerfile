# Use official lightweight Python image
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Copy files
COPY app.py ./
COPY templates ./templates

# Install Flask
RUN pip install flask

# Expose Flask port
EXPOSE 5000

# Run the app
CMD ["python", "app.py"]
