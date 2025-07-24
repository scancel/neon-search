# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set the working directory in the container
WORKDIR /code

# Copy the dependencies file to the working directory
COPY ./requirements.txt .

# Install any needed packages specified in requirements.txt
# Use --no-cache-dir to reduce image size
RUN pip install --no-cache-dir --upgrade -r requirements.txt

# Copy the rest of the application's code to the working directory
COPY ./app /code/app
COPY ./frontend /code/frontend

# Command to run the application
# Uvicorn is a lightning-fast ASGI server, running on port 80
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "80"]
