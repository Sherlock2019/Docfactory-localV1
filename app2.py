import os
import secrets
from flask import Flask, render_template, request, send_from_directory, jsonify
from werkzeug.utils import secure_filename
import logging
from datetime import datetime

# Import utilities
from utils.document_filler import fill_document_template
from utils.extract_placeholders import extract_placeholders

# Set up logging
logging.basicConfig(level=logging.DEBUG)

app = Flask(__name__)

# --- Configuration ---
# Generate a random secret key for session management
app.secret_key = secrets.token_hex(16)

# Define upload and output directories
UPLOAD_FOLDER = 'uploads'
OUTPUT_FOLDER = 'generated_documents'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['OUTPUT_FOLDER'] = OUTPUT_FOLDER

# Create directories if they don't exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(OUTPUT_FOLDER, exist_ok=True)

GENERATED_DOCS = []

# Global placeholder list (for text inputs)
KEY_FIELDS = ["CUSTOMER_NAME", "CITY_NAME", "COUNTRY", "SA_EMAIL", "PARTNER_NAME", "DATE"]

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

    if not tpl.filename.lower().endswith((".docx", ".pptx")):
        return jsonify({"error": "Only .docx and .pptx templates are supported."}), 400

    try:
        temp_tpl_path = os.path.join(app.config['UPLOAD_FOLDER'], secure_filename(tpl.filename))
        tpl.save(temp_tpl_path)
        
        placeholders = extract_placeholders(temp_tpl_path)
        
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

    file_extension = tpl.filename.lower().rsplit(".", 1)[-1]
    if file_extension not in ("docx", "pptx"):
        return jsonify({"error": "Only .docx and .pptx templates are supported for generation."}), 400

    template_filename = secure_filename(tpl.filename)
    template_path = os.path.join(app.config['UPLOAD_FOLDER'], template_filename)
    tpl.save(template_path)

    text_inputs = {}
    file_inputs = {}

    # Get the document type from the form data
    doc_type = request.form.get("doc_type", "Document").replace(" ", "-") # Get and sanitize doc_type

    # Collect text inputs, excluding 'doc_type' which is handled separately for the filename
    for key, value in request.form.items():
        if key not in ['template', 'doc_type', 'doc_type_select', 'custom_doc_type']: # Exclude form internal fields
            text_inputs[key] = value

    for key, file_storage in request.files.items():
        if key != 'template' and file_storage.filename != '':
            file_inputs[key] = file_storage

    # Generate a unique output filename in the format: typeofdoc-customername-partnername-SAname-date
    # Sanitize inputs for filename
    customer_name = text_inputs.get("CUSTOMER_NAME", "UnknownCustomer").replace(" ", "_")
    partner_name = text_inputs.get("PARTNER_NAME", "NoPartner").replace(" ", "_")
    sa_name = text_inputs.get("SA_EMAIL", "NoSA").replace(" ", "_").split('@')[0] # Use email prefix for SA name
    current_date_for_filename = datetime.now().strftime("%Y%m%d")
    
    # Construct filename
    output_filename = f"{doc_type}-{customer_name}-{partner_name}-{sa_name}-{current_date_for_filename}.{file_extension}"
    output_path = os.path.join(app.config['OUTPUT_FOLDER'], output_filename)

    try:
        fill_document_template(template_path, file_inputs, text_inputs, output_path)

        GENERATED_DOCS.append(output_filename) 

        return jsonify({"message": "Document generated successfully!", "filename": output_filename}), 200

    except Exception as e:
        logging.error(f"Document generation failed: {e}")
        return jsonify({"error": f"Document generation failed: {e}"}), 500

@app.route("/list_generated_files", methods=["GET"])
def list_generated_files():
    files_in_folder = []
    for f in os.listdir(app.config['OUTPUT_FOLDER']):
        full_path = os.path.join(app.config['OUTPUT_FOLDER'], f)
        if os.path.isfile(full_path):
            files_in_folder.append({
                "name": f,
                "timestamp": os.path.getmtime(full_path)
            })
    
    files_in_folder.sort(key=lambda x: x['timestamp'], reverse=True)
    
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

