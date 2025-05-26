#!/bin/bash
# This script updates the DocFactory application files and then launches the Flask app.

# Exit immediately if a command exits with a non-zero status.
set -e

echo "--- DocFactory Update and Launch Script ---"

# Define the project root (assuming script is run from the project's base directory)
PROJECT_ROOT=$(pwd)

echo "Ensuring project directories exist..."
mkdir -p "$PROJECT_ROOT/utils"
mkdir -p "$PROJECT_ROOT/templates"
mkdir -p "$PROJECT_ROOT/static"

echo "Creating/updating __init__.py in utils folder..."
touch "$PROJECT_ROOT/utils/__init__.py"

echo "Replacing app.py..."
cat << 'EOF' > "$PROJECT_ROOT/app.py"
# app.py
from flask import Flask, render_template, request, send_file, url_for, abort
from utils.extract_placeholders import extract_placeholders
from utils.document_filler import fill_document_template
from uuid import uuid4
import os
import tempfile
from datetime import date

app = Flask(__name__)

# The specific "key" text fields from the CRA template
KEY_FIELDS = [
    "CUSTOMER_NAME",
    "CITY_NAME",
    "COUNTRY",
    "SA_EMAIL",
    "RAX_TEAM",
    "PARTNER_NAME",
    "TCO_YEAR",
    "Date" # For the version date
]

@app.route("/", methods=["GET"])
def index():
    # Renders the bare-bones HTML/JS shell
    return render_template("index.html", KEY_FIELDS=KEY_FIELDS)

@app.route("/analyze", methods=["POST"])
def analyze():
    if "template" not in request.files:
        return {"error": "No template file provided"}, 400

    tpl = request.files["template"]
    if tpl.filename == '':
        return {"error": "No selected template file"}, 400

    # >>> START DEBUG PRINTS (KEEP THESE!) <<<
    print(f"DEBUG: Received filename: {tpl.filename}")
    print(f"DEBUG: Filename lowercase: {tpl.filename.lower()}")
    file_extension = tpl.filename.lower().rsplit(".", 1)[-1]
    print(f"DEBUG: Extracted extension: {file_extension}")
    # >>> END DEBUG PRINTS <<<

    if file_extension not in (".docx", ".pptx"):
        return {"error": "Only .docx and .pptx templates are supported."}, 400

    # Save uploaded template temporarily for analysis
    with tempfile.NamedTemporaryFile(delete=False, suffix=f".{file_extension}") as tmp_tpl:
        tpl.save(tmp_tpl.name)
        tmp_path = tmp_tpl.name

    try:
        # Extract ALL placeholders, preserving their document order
        placeholders = extract_placeholders(tmp_path)
    except Exception as e:
        # >>> THIS IS WHERE THE ERROR MESSAGE WILL BE PRINTED IF EXTRACTION FAILS <<<
        print(f"ERROR: Exception during placeholder extraction: {e}")
        return {"error": f"Error analyzing template: {e}"}, 500
    finally:
        os.unlink(tmp_path) # Clean up the temporary template file immediately

    # Return them in one ordered list
    return {"placeholders": placeholders}

@app.route("/generate", methods=["POST"])
def generate():
    if "template" not in request.files:
        return {"error": "No template file provided for generation"}, 400

    tpl = request.files["template"]
    if tpl.filename == '':
        return {"error": "No selected template file for generation"}, 400

    file_extension = tpl.filename.lower().rsplit(".", 1)[-1]
    if file_extension not in ("docx", "pptx"):
        return {"error": "Only .docx and .pptx templates are supported for generation."}, 400

    # Save the template file temporarily for processing
    with tempfile.NamedTemporaryFile(delete=False, suffix=f".{file_extension}") as tmp_tpl:
        tpl.save(tmp_tpl.name)
        tpl_path = tmp_tpl.name

    text_inputs = {
        key: request.form.get(key, "")
        for key in KEY_FIELDS
    }

    # Automatically fill the 'Date' placeholder with today's date if it's a KEY_FIELD
    if "Date" in KEY_FIELDS:
        text_inputs["Date"] = date.today().strftime("%Y-%m-%d") # Or whatever format you prefer

    file_inputs = {}
    for key in request.files:
        if key != "template" and key not in KEY_FIELDS: # Exclude the template file itself
            f = request.files[key]
            if f and f.filename:
                file_inputs[key] = f # Pass the FileStorage object directly

    # Generate output filename
    customer_name = text_inputs.get("CUSTOMER_NAME", "UnknownCustomer").replace(" ", "_")
    partner_name = text_inputs.get("PARTNER_NAME", "UnknownPartner").replace(" ", "_")
    sa_email_prefix = text_inputs.get("SA_EMAIL", "UnknownSA").split('@')[0].replace(".", "_") # Handle dots in email prefix
    today_str_for_filename = date.today().strftime("%Y%m%d")

    # Construct the base filename, preserving the original extension
    output_filename_base = f"CRA_{customer_name}_{partner_name}_{sa_email_prefix}_{today_str_for_filename}"
    out_filename = f"{output_filename_base}.{file_extension}"

    # Generate and send back
    with tempfile.NamedTemporaryFile(delete=False, suffix=f".{file_extension}") as tmp_out:
        out_path = tmp_out.name

    try:
        fill_document_template(tpl_path, file_inputs, text_inputs, out_path)
    except ValueError as e:
        return {"error": str(e)}, 400
    except Exception as e:
        return {"error": f"Document generation failed: {e}"}, 500
    finally:
        os.unlink(tpl_path) # Clean up the temporary template file

    try:
        # Instead of directly sending the file, we'll render a page with a download link
        # and a "Start New" button.
        download_url = url_for('download_file', filename=os.path.basename(out_path), original_name=out_filename)
        return render_template("download_complete.html", download_url=download_url, out_filename=out_filename)
    except Exception as e:
        # If sending file fails, try to clean up
        if os.path.exists(out_path):
            os.unlink(out_path)
        return {"error": f"Error preparing download: {e}"}, 500


# New route to serve the generated file
@app.route("/download/<path:filename>")
def download_file(filename):
    # Construct the full path to the temporary file
    temp_file_path = os.path.join(tempfile.gettempdir(), filename) # tempfile.gettempdir() gives /tmp on linux

    # Get the original desired download name (passed from generate route)
    original_name = request.args.get('original_name', filename)

    # Determine mimetype based on extension
    file_extension = original_name.lower().rsplit(".", 1)[-1]
    mimetype = f"application/vnd.openxmlformats-officedocument.{'wordprocessingml.document' if file_extension == 'docx' else 'presentationml.presentation'}"

    if not os.path.exists(temp_file_path):
        abort(404, description="File not found or already downloaded.")

    try:
        return send_file(temp_file_path,
                         as_attachment=True,
                         download_name=original_name,
                         mimetype=mimetype)
    finally:
        # Clean up the generated file after it's sent.
        # Note: This might cause issues if the user navigates away before download completes.
        # For production, consider a scheduled cleanup job or a temporary file system.
        os.unlink(temp_file_path)

if __name__=="__main__":
    app.run(debug=True)
EOF

echo "Replacing utils/extract_placeholders.py..."
cat << 'EOF' > "$PROJECT_ROOT/utils/extract_placeholders.py"
import re
from docx import Document
from pptx import Presentation
from io import BytesIO # Needed for handling in-memory files

def extract_placeholders(file_path_or_stream):
    """
    Extracts placeholders from a .docx or .pptx file.
    Placeholders are expected in the format {PLACEHOLDER_NAME}.
    Returns an ordered list of unique placeholders found.
    """
    placeholders = []
    text_content = ""
    file_extension = ""

    # Determine if input is a path or a stream
    if isinstance(file_path_or_stream, str):
        file_extension = file_path_or_stream.lower().rsplit(".", 1)[-1]
        source = file_path_or_stream
    elif isinstance(file_path_or_stream, BytesIO):
        # When handling BytesIO, we need the original filename or mime type
        # for proper extension determination. Assuming the caller passes it
        # via another argument if needed, or we rely on the processing logic
        # in document_filler to pass it correctly for temp files.
        # For this function, let's assume it's passed as path, or handled by caller for streams.
        # Re-evaluating: The app.py passes a tmp_path (string) for analyze, so this is fine.
        # For extract_text_from_file, it can be a stream.

        # If a BytesIO object is passed, try to determine its type or handle as text.
        # For placeholder extraction, it's typically a file path because we save the uploaded file.
        # So, the 'file_path_or_stream' here should usually be a string path.
        raise ValueError("extract_placeholders expects a file path (string), not a stream, for initial analysis.")
    else:
        raise TypeError("Invalid input type for file_path_or_stream. Must be a string (file path).")


    if file_extension == "docx":
        doc = Document(source)
        for paragraph in doc.paragraphs:
            text_content += paragraph.text + "\n"
        for table in doc.tables:
            for row in table.rows:
                for cell in row.cells:
                    text_content += cell.text + "\n"
    elif file_extension == "pptx":
        prs = Presentation(source)
        for slide in prs.slides:
            for shape in slide.shapes:
                if hasattr(shape, "text_frame") and shape.text_frame:
                    text_content += shape.text_frame.text + "\n"
    else:
        # This case should ideally be caught by app.py's initial validation
        raise ValueError(f"Unsupported file type for placeholder extraction: .{file_extension}")

    # Find all placeholders in the text content
    found_placeholders = re.findall(r"{([A-Za-z0-9_]+)}", text_content)

    # Return unique placeholders in order of first appearance
    unique_placeholders = []
    seen = set()
    for ph in found_placeholders:
        if ph not in seen:
            unique_placeholders.append(ph)
            seen.add(ph)

    return unique_placeholders


def extract_text_from_file(file_stream, filename):
    """
    Extracts text content from various file types (txt, docx, pptx)
    given a file stream and its original filename.
    """
    file_extension = filename.lower().rsplit(".", 1)[-1]
    text_content = ""

    if file_extension == "txt":
        file_stream.seek(0)
        text_content = file_stream.read().decode('utf-8')
    elif file_extension == "docx":
        doc = Document(file_stream) # python-docx can take a stream
        for paragraph in doc.paragraphs:
            text_content += paragraph.text + "\n"
        for table in doc.tables:
            for row in table.rows:
                for cell in row.cells:
                    text_content += cell.text + "\n"
    elif file_extension == "pptx":
        prs = Presentation(file_stream) # python-pptx can take a stream
        for slide in prs.slides:
            for shape in slide.shapes:
                if hasattr(shape, "text_frame") and shape.text_frame:
                    text_content += shape.text_frame.text + "\n"
    else:
        # For other file types, you might return an empty string or raise an error
        print(f"WARNING: Attempted to extract text from unsupported file type: {filename}")
        return "" # Or raise ValueError("Unsupported file type for text extraction")

    return text_content.strip()
EOF

echo "Replacing utils/document_filler.py..."
cat << 'EOF' > "$PROJECT_ROOT/utils/document_filler.py"
import re
import os
from io import BytesIO
from datetime import date
from docx import Document
from docx.shared import Inches
from docx.oxml.shared import OxmlElement, qn # Needed for inserting elements
from docx.enum.text import WD_ALIGN_PARAGRAPH # For table alignment
from pptx import Presentation
from pptx.util import Inches as PptxInches
import pandas as pd
import uuid

from utils.extract_placeholders import extract_text_from_file

# Helper function to insert a new element (like a table) after a reference element
def insert_element_after(parent, child, reference):
    """Inserts a child XML element immediately after a reference XML element within the parent."""
    parent.insert(parent.index(reference) + 1, child)


def fill_document_template(
    tpl_path: str,
    file_inputs: dict[str, "werkzeug.datastructures.FileStorage"],
    text_inputs: dict[str, str],
    out_path: str
):
    """
    Fills a .docx or .pptx template using both text and file-based placeholder values.

    Args:
    - tpl_path:      Path to the input .docx or .pptx template
    - file_inputs:   Dict mapping placeholder -> FileStorage (uploaded file)
    - text_inputs:   Dict mapping placeholder -> raw string (manual entry)
    - out_path:      Where to write the final filled document
    """
    file_extension = tpl_path.lower().rsplit(".", 1)[-1]
    today_str = date.today().strftime("%Y-%m-%d")

    if file_extension == "docx":
        doc = Document(tpl_path)
        # We re-extract placeholders here for robustness, though app.py already does.
        # This ensures we have the current state of the placeholders in the document being filled.
        # Note: If the document filler modifies the document structure before all placeholders are found,
        # re-extracting might be problematic. For this approach, we find and replace directly.

        # Store paragraphs and their XML element references for efficient manipulation
        # Convert to list to allow modification during iteration
        doc_paragraphs = list(doc.paragraphs)
        
        # Build a list of (paragraph_object, its_xml_element) for all paragraphs
        # This allows us to modify the XML tree accurately.
        paragraph_elements = [(p, p._element) for p in doc.paragraphs]
        doc_body = doc.element.body # The main body XML element

        # Pre-process text_inputs (including auto-filled 'Date')
        all_inputs = text_inputs.copy()
        if "Date" in all_inputs: # Ensure auto-filled Date is available
            all_inputs["Date"] = date.today().strftime("%Y-%m-%d")

        # Iterate through paragraphs to find and replace
        # It's safer to iterate and handle removals/insertions carefully.
        # We will iterate on a copy of the list of paragraphs,
        # but operate on the live document.
        
        # A more robust way to handle dynamic insertions (like tables and images)
        # is to keep track of the XML elements directly.

        # This outer loop ensures we process all defined KEY_FIELDS and file_inputs
        # regardless of their order in the document.
        # We need to iterate through all placeholders and find them in the document.
        # Re-indexing paragraphs after each deletion/insertion is complex.
        # The current 'in-place' table insertion for DOCX requires careful XML manipulation.

        # First pass: Handle text placeholders
        for paragraph in doc.paragraphs:
            for key, value in all_inputs.items():
                tag = f"{{{key}}}"
                if tag in paragraph.text:
                    paragraph.text = paragraph.text.replace(tag, str(value))
        
        for table in doc.tables:
            for row in table.rows:
                for cell in row.cells:
                    for key, value in all_inputs.items():
                        tag = f"{{{key}}}"
                        if tag in cell.text:
                            cell.text = cell.text.replace(tag, str(value))

        # Second pass: Handle file inputs (images, Excel, other docs)
        # This requires more complex manipulation of the document's XML structure.
        # We need to find the specific paragraph containing the placeholder,
        # then replace or insert content at that XML location.
        
        # Iterate through a fresh list of paragraphs after text replacement
        # to ensure we find the target paragraphs for file insertions.
        updated_paragraphs = list(doc.paragraphs) # Get current state of paragraphs
        
        # Using a list of (paragraph_object, placeholder_tag) that need file insertion
        file_placeholder_targets = []
        for ph_name, file_storage in file_inputs.items():
            if not file_storage or not file_storage.filename:
                continue # Skip if no file uploaded for this placeholder

            tag = f"{{{ph_name}}}"
            found_in_doc = False
            
            # Find in paragraphs
            for p in updated_paragraphs:
                if tag in p.text:
                    file_placeholder_targets.append((p, ph_name, file_storage))
                    found_in_doc = True
                    break # Assuming one placeholder per paragraph for file inputs

            # You might also want to search tables if file placeholders could be in cells,
            # but inserting images/tables into cells is much more complex and often avoided.
            # For simplicity, we assume file inputs are in their own paragraph.

        # Process file placeholder targets
        for p_obj, ph_name, file_storage in file_placeholder_targets:
            tag = f"{{{ph_name}}}"
            p_elm = p_obj._element # Get the XML element of the target paragraph
            p_parent = p_elm.getparent() # Get the parent of the paragraph (usually body)

            if ph_name == "PROJECT_DATA_TABLE" and file_storage.filename.lower().endswith(".xlsx"):
                file_storage.stream.seek(0)
                try:
                    df = pd.read_excel(file_storage.stream)

                    # Create a new table element. Python-docx adds it to the end by default.
                    temp_table = doc.add_table(rows=1, cols=len(df.columns))
                    temp_table.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    # Apply a style if you have one, e.g., temp_table.style = 'Table Grid'

                    # Populate table headers
                    hdr_cells = temp_table.rows[0].cells
                    for j, col in enumerate(df.columns):
                        hdr_cells[j].text = str(col)

                    # Populate table data
                    for _, row in df.iterrows():
                        row_cells = temp_table.add_row().cells
                        for j, cell in enumerate(row):
                            row_cells[j].text = str(cell)

                    temp_table_elm = temp_table._tbl # Get the underlying XML element of the table

                    # Remove the temp_table_elm from its default position at the end of the document
                    if temp_table_elm.getparent() is not None:
                        temp_table_elm.getparent().remove(temp_table_elm)

                    # Insert the table's XML element directly after the placeholder paragraph's XML element
                    insert_element_after(p_parent, temp_table_elm, p_elm)

                    # Remove the placeholder paragraph's XML element
                    p_parent.remove(p_elm)

                except Exception as e:
                    # If Excel reading fails, insert an error message in place of the placeholder
                    print(f"WARNING: Failed to insert Excel table for {ph_name}: {e}")
                    p_obj.text = p_obj.text.replace(tag, f"[ERROR: Could not insert Excel table - {e}]")
                finally:
                    file_storage.stream.seek(0) # Reset stream after reading

            elif file_storage.filename.lower().endswith((".png", ".jpg", ".jpeg", ".gif", ".bmp")):
                file_storage.stream.seek(0)
                img_data = file_storage.read()
                
                # Replace the entire paragraph with the image
                p_parent.remove(p_elm) # Remove the placeholder paragraph
                
                # Create a new paragraph where the image will be inserted
                # This new paragraph will be inserted where the old one was
                new_p = doc_body.add_paragraph()
                insert_element_after(p_parent, new_p._element, p_elm if p_elm.getprevious() is None else p_elm.getprevious()) # Adjust insertion point

                # Write image to a temporary file, then add to run
                tmp_img_path = f"/tmp/{uuid.uuid4()}_{file_storage.filename}"
                with open(tmp_img_path, "wb") as tmp:
                    tmp.write(img_data)
                new_p.add_run().add_picture(tmp_img_path, width=Inches(4)) # Adjust width as needed
                os.remove(tmp_img_path)
                file_storage.stream.seek(0) # Reset stream

            elif file_storage.filename.lower().endswith((".txt", ".docx", ".pptx")):
                file_storage.stream.seek(0)
                extracted_text = extract_text_from_file(file_storage.stream, file_storage.filename)
                # Overwrite the paragraph's text with extracted content
                # This removes the original placeholder text
                p_obj.text = p_obj.text.replace(tag, extracted_text)
                file_storage.stream.seek(0) # Reset stream

            else:
                # Handle unknown file types for file inputs
                print(f"WARNING: Unhandled file type for placeholder {ph_name}: {file_storage.filename}")
                p_obj.text = p_obj.text.replace(tag, f"[UNSUPPORTED FILE TYPE: {file_storage.filename}]")
                file_storage.stream.seek(0) # Reset stream

        doc.save(out_path)

    elif file_extension == "pptx":
        prs = Presentation(tpl_path)
        # Placeholders are dynamically extracted in app.py and sent here.
        # For PPTX, direct in-place replacement for images/tables is not supported
        # in python-pptx as robustly as docx. We replace text or add to slide.

        # First pass: Handle text placeholders
        for slide in prs.slides:
            for shape in slide.shapes:
                if hasattr(shape, "text_frame") and shape.text_frame:
                    for key, value in all_inputs.items(): # Use all_inputs including Date
                        tag = f"{{{key}}}"
                        if tag in shape.text_frame.text:
                            shape.text_frame.text = shape.text_frame.text.replace(tag, str(value))
        
        # Second pass: Handle file inputs
        for slide in prs.slides:
            for shape in slide.shapes:
                if hasattr(shape, "text_frame") and shape.text_frame:
                    for ph_name, file_storage in file_inputs.items():
                        if not file_storage or not file_storage.filename:
                            continue # Skip if no file uploaded

                        tag = f"{{{ph_name}}}"
                        if tag in shape.text_frame.text:
                            if file_storage.filename.lower().endswith((".png", ".jpg", ".jpeg", ".gif", ".bmp")):
                                # For PPTX, cannot easily replace text placeholder with an image in-place.
                                # Replace with a message and optionally add the image at a fixed spot.
                                shape.text_frame.text = shape.text_frame.text.replace(tag, f"[IMAGE: {file_storage.filename} - Inserted below or on slide]")
                                try:
                                    # Example: Add image to slide, not in place of text
                                    file_storage.stream.seek(0)
                                    slide.shapes.add_picture(BytesIO(file_storage.read()), PptxInches(1), PptxInches(1), PptxInches(4))
                                except Exception as e:
                                    print(f"WARNING: Could not insert image {file_storage.filename} into PPTX: {e}")
                                finally:
                                    file_storage.stream.seek(0)

                            elif ph_name == "PROJECT_DATA_TABLE" and file_storage.filename.lower().endswith(".xlsx"):
                                # For PPTX, cannot easily insert Excel table in-place.
                                # Replace with a message. You could generate an image of the table and insert that.
                                shape.text_frame.text = shape.text_frame.text.replace(tag, f"[EXCEL TABLE: {file_storage.filename} - Insert manually]")
                                file_storage.stream.seek(0) # Reset stream

                            elif file_storage.filename.lower().endswith((".txt", ".docx", ".pptx")):
                                file_storage.stream.seek(0)
                                extracted_text = extract_text_from_file(file_storage.stream, file_storage.filename)
                                shape.text_frame.text = shape.text_frame.text.replace(tag, extracted_text)
                                file_storage.stream.seek(0) # Reset stream
                            else:
                                print(f"WARNING: Unhandled file type for placeholder {ph_name} in PPTX: {file_storage.filename}")
                                shape.text_frame.text = shape.text_frame.text.replace(tag, f"[UNSUPPORTED FILE TYPE: {file_storage.filename}]")
                                file_storage.stream.seek(0) # Reset stream

        prs.save(out_path)
    else:
        raise ValueError(f"Unsupported template file type: .{file_extension}")
EOF

echo "Replacing templates/index.html..."
cat << 'EOF' > "$PROJECT_ROOT/templates/index.html"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>DocFactory</title>
  <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">
</head>
<body>
  <h1>📄 Fill in your placeholders</h1>

  <!-- STEP 1: Template Upload -->
  <section id="uploader">
    <form id="tplForm" enctype="multipart/form-data">
      <label>Select your .docx or .pptx template:</label>
      <input type="file" name="template" accept=".docx,.pptx" required>
      <button type="submit">Analyze Template</button>
    </form>
  </section>

  <!-- STEP 2: Dynamic Inputs will be injected here -->
  <section id="fields" style="display:none">
    <form id="genForm" enctype="multipart/form-data" method="POST" action="{{ url_for('generate') }}">
      <div id="inputsContainer"></div>
      <button type="submit">Generate Document</button>
    </form>
  </section>

  <script>
    const KEY_FIELDS = {{ KEY_FIELDS|tojson }};

    // Analyze form → build dynamic fields
    document.getElementById('tplForm').addEventListener('submit', async ev => {
      ev.preventDefault();
      const form = ev.target;
      const data = new FormData(form);
      
      const tplFile = form.querySelector('input[name=template]').files[0];
      data.append('template', tplFile);

      try {
          const res = await fetch('/analyze', { method:'POST', body:data });
          const jsonResponse = await res.json();

          if (res.ok) {
              const { placeholders } = jsonResponse;

              // Hide uploader, show generator
              document.getElementById('uploader').style.display = 'none';
              document.getElementById('fields').style.display = '';

              // Create a hidden input for the template file in the second form
              const fileInputClone = document.createElement('input');
              fileInputClone.type = 'file';
              fileInputClone.name = 'template';
              
              const dataTransfer = new DataTransfer();
              dataTransfer.items.add(tplFile);
              fileInputClone.files = dataTransfer.files;
              
              fileInputClone.style.display = 'none';
              document.getElementById('genForm').appendChild(fileInputClone);

              // Build inputs in order
              const container = document.getElementById('inputsContainer');
              container.innerHTML = ''; // Clear previous inputs if any (e.g. if user navigates back)

              placeholders.forEach(ph => {
                const div = document.createElement('div');
                div.className = 'form-group';
                const label = document.createElement('label');
                label.textContent = ph;
                div.appendChild(label);

                if (KEY_FIELDS.includes(ph)) {
                  // text input
                  const inp = document.createElement('input');
                  inp.type = 'text';
                  inp.name = ph;
                  // Make required for key identifiers if needed, but 'Date' is auto-filled
                  if (["CUSTOMER_NAME", "PARTNER_NAME", "SA_EMAIL"].includes(ph)) {
                    inp.required = true;
                  }
                  div.appendChild(inp);
                } else {
                  // file input
                  const inp = document.createElement('input');
                  inp.type = 'file';
                  inp.name = ph;
                  inp.accept = 'image/*,.docx,.pptx,.xlsx,.txt';
                  div.appendChild(inp);
                }

                container.appendChild(div);
              });
          } else {
              alert('Error analyzing template: ' + (jsonResponse.error || 'Unknown error'));
              // Optionally, reset form or hide fields if analyze fails
              document.getElementById('uploader').style.display = '';
              document.getElementById('fields').style.display = 'none';
          }
      } catch (error) {
          console.error('Fetch error:', error);
          alert('Network error or server unavailable during template analysis.');
          document.getElementById('uploader').style.display = '';
          document.getElementById('fields').style.display = 'none';
      }
    });
  </script>
</body>
</html>
EOF

echo "Replacing templates/download_complete.html..."
cat << 'EOF' > "$PROJECT_ROOT/templates/download_complete.html"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>DocFactory - Download Complete</title>
  <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">
</head>
<body>
  <h1>✅ Document Generated Successfully!</h1>

  <section>
    <p>Your document "<strong>{{ out_filename }}</strong>" is ready.</p>
    <a href="{{ download_url }}" download="{{ out_filename }}" class="button-link">Download Document</a>
  </section>

  <section style="margin-top: 2em;">
    <p>Ready to start a new document?</p>
    <button onclick="window.location.href='/'">Start New Template</button>
  </section>

  <style>
    /* Add specific styles for download button if needed */
    .button-link {
        display: inline-block;
        background: #28a745; /* Green color */
        color: white;
        border: none;
        padding: 0.8em 1.5em;
        font-size: 1.1em;
        cursor: pointer;
        text-decoration: none; /* Remove underline */
        border-radius: 4px; /* Slightly rounded corners */
        text-align: center;
    }
    .button-link:hover {
        background: #218838; /* Darker green on hover */
    }
  </style>
</body>
</html>
EOF

echo "Replacing static/style.css..."
cat << 'EOF' > "$PROJECT_ROOT/static/style.css"
body {
    font-family: Arial, sans-serif;
    margin: 20px;
    background-color: #f4f4f4;
    color: #333;
}

h1 {
    color: #0056b3;
    text-align: center;
}

section {
    background-color: #fff;
    padding: 20px;
    margin-bottom: 20px;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

label {
    display: block;
    margin-bottom: 8px;
    font-weight: bold;
}

input[type="text"],
input[type="file"] {
    width: calc(100% - 22px); /* Adjust for padding and border */
    padding: 10px;
    margin-bottom: 15px;
    border: 1px solid #ddd;
    border-radius: 4px;
    box-sizing: border-box; /* Include padding and border in the element's total width and height */
}

button {
    background-color: #007bff;
    color: white;
    border: none;
    padding: 10px 20px;
    font-size: 16px;
    border-radius: 5px;
    cursor: pointer;
    transition: background-color 0.3s ease;
}

button:hover {
    background-color: #0056b3;
}

.form-group {
    margin-bottom: 15px;
}
EOF

echo "Installing/updating Python dependencies..."
# It's good practice to activate the virtual environment if it exists.
# This assumes 'venv' is the name of your virtual environment folder.
if [ -d "$PROJECT_ROOT/venv" ]; then
    source "$PROJECT_ROOT/venv/bin/activate"
    echo "Virtual environment activated."
else
    echo "No virtual environment 'venv' found. Installing to system Python or current environment."
fi

pip install Flask python-docx python-pptx pandas openpyxl Pillow

echo "Launching the Flask application..."
python "$PROJECT_ROOT/app.py"


