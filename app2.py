import os
import secrets
from flask import Flask, render_template, request, send_from_directory, jsonify
from werkzeug.utils import secure_filename
import logging
from datetime import datetime

# Import utilities
from utils.document_filler import fill_document_template
from utils.extract_placeholders import extract_placeholders # Make sure this is correctly imported from utils.extract_placeholders

# Set up logging
logging.basicConfig(level=logging.DEBUG)

app = Flask(__name__)

# --- Configuration ---
# Generate a random secret key for session management
app.secret_key = secrets.token_hex(16)

# Define upload and output directories
UPLOAD_FOLDER = 'uploads'
OUTPUT_FOLDER = 'generated_documents' # New folder for generated files
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['OUTPUT_FOLDER'] = OUTPUT_FOLDER

# Create directories if they don't exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(OUTPUT_FOLDER, exist_ok=True)

# In-memory list to store generated document names
# For a production app, this should be replaced with a database (e.g., SQLite, PostgreSQL)
# or a more robust persistent storage solution.
GENERATED_DOCS = []

# Global placeholder list (e.g., for key fields like customer name)
# This could also be loaded from a config file.
KEY_FIELDS = ["CUSTOMER_NAME", "PARTNER_NAME", "SA_EMAIL"]

# --- Routes ---

@app.route("/")
def index():
    return render_template("index.html", KEY_FIELDS=KEY_FIELDS)

@app.route("/analyze", methods=["POST"])
def analyze():
    if 'template' not in request.files:
        return jsonify({"error": "No template file part"}), 400

    tpl = request.files['template']
    if tpl.filename == '':
        return jsonify({"error": "No selected file"}), 400

    # Ensure the file is a DOCX or PPTX for analysis
    if not tpl.filename.lower().endswith((".docx", ".pptx")):
        return jsonify({"error": "Only .docx and .pptx templates are supported."}), 400

    try:
        # Save the template temporarily to analyze it
        # You might want to save it with a unique name if you want to store it longer
        temp_tpl_path = os.path.join(app.config['UPLOAD_FOLDER'], secure_filename(tpl.filename))
        tpl.save(temp_tpl_path)
        
        placeholders = extract_placeholders(temp_tpl_path)
        
        # Optionally, remove the temporary template after analysis if not needed for generation
        # os.remove(temp_tpl_path) 
        
        # Send a success response with placeholders
        return jsonify({"placeholders": placeholders}), 200

    except Exception as e:
        logging.error(f"Error analyzing template: {e}")
        return jsonify({"error": f"Error analyzing template: {e}"}), 500


@app.route("/generate", methods=["POST"])
def generate():
    if 'template' not in request.files:
        return jsonify({"error": "No template file part in generation request"}), 400

    tpl = request.files['template']
    if tpl.filename == '':
        return jsonify({"error": "No template file selected for generation"}), 400

    # Ensure the file extension is valid for generation
    file_extension = tpl.filename.lower().rsplit(".", 1)[-1]
    if file_extension not in ("docx", "pptx"):
        return jsonify({"error": "Only .docx and .pptx templates are supported for generation."}), 400

    # Save the template
    template_filename = secure_filename(tpl.filename)
    template_path = os.path.join(app.config['UPLOAD_FOLDER'], template_filename)
    tpl.save(template_path) # Save the template file for processing

    text_inputs = {}
    file_inputs = {}

    # Collect text and file inputs
    for key, value in request.form.items():
        if key in KEY_FIELDS or '{' + key + '}' in request.form: # Check if it's a known text field
             text_inputs[key] = value

    for key, file_storage in request.files.items():
        if key != 'template' and file_storage.filename != '':
            # Store the FileStorage object itself to pass to document_filler
            file_inputs[key] = file_storage

    # Generate a unique output filename
    # Example: "Generated_Document_CUSTOMER_NAME_YYYYMMDD_HHMMSS.docx"
    customer_name = text_inputs.get("CUSTOMER_NAME", "UnknownCustomer").replace(" ", "_")
    current_time = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_filename = f"Generated_Doc_{customer_name}_{current_time}.{file_extension}"
    output_path = os.path.join(app.config['OUTPUT_FOLDER'], output_filename)

    try:
        fill_document_template(template_path, file_inputs, text_inputs, output_path)

        # Add the generated filename to our in-memory list
        GENERATED_DOCS.append(output_filename)

        # Remove the temporary template after generation (optional)
        # os.remove(template_path)

        # Return a success message or the filename so frontend can display
        return jsonify({"message": "Document generated successfully!", "filename": output_filename}), 200

    except Exception as e:
        logging.error(f"Document generation failed: {e}")
        return jsonify({"error": f"Document generation failed: {e}"}), 500

@app.route("/list_generated_files", methods=["GET"])
def list_generated_files():
    # Sort files by modification date (newest first) or alphabetically
    # For a persistent solution, file names would come from a DB
    # For now, we list from the folder, and sort the in-memory list.
    
    # It's better to read directly from the directory if GENERATED_DOCS is not robustly managed
    files_in_folder = []
    for f in os.listdir(app.config['OUTPUT_FOLDER']):
        full_path = os.path.join(app.config['OUTPUT_FOLDER'], f)
        if os.path.isfile(full_path):
            files_in_folder.append({
                "name": f,
                "timestamp": os.path.getmtime(full_path) # Get modification time for sorting
            })
    
    # Sort by timestamp (newest first)
    files_in_folder.sort(key=lambda x: x['timestamp'], reverse=True)
    
    # Return just the names
    return jsonify([f['name'] for f in files_in_folder]), 200

@app.route("/download/<filename>")
def download_file(filename):
    try:
        return send_from_directory(app.config['OUTPUT_FOLDER'], filename, as_attachment=True)
    except FileNotFoundError:
        return jsonify({"error": "File not found."}), 404
    except Exception as e:
        logging.error(f"Error serving file {filename}: {e}")
        return jsonify({"error": f"Error downloading file: {e}"}), 500

if __name__ == "__main__":
    app.run(debug=True)

