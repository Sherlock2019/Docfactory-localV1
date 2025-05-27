<img width="341" alt="image" src="https://github.com/user-attachments/assets/5578fb0b-dd64-44a9-a5f7-7cfd6c06a8f1" />


# 📄 Let s Build  Docs Faster , Easier , Better , with less Human error and Repeat ...



DocFactory is a smart document generator for teams who need to automate DOCX and PPTX production from templates. Upload your template with `{placeholders}`, enter text or upload content for each field, and generate a ready-to-deliver document in seconds.

---

## 🚀 Features

| Feature                          | Description                                                                 |
|----------------------------------|-----------------------------------------------------------------------------|
| 🧠 Smart Placeholder Detection   | Extracts `{placeholders}` from uploaded .docx or .pptx in **document order** |
| ✍️ Text Input for Key Fields     | Input text values for key business fields like `{CUSTOMER_NAME}`, `{CITY_NAME}` |
| 📁 File Uploads for Rich Fields  | Upload content (.docx, .pptx, .txt, .xlsx, .jpg, .png) for auto-conversion |
| 📊 Excel → Word Table Conversion | Upload `.xlsx` and have it rendered as a table in the generated DOCX       |
| 🖼️ Image Embedding in DOCX       | Upload logos, diagrams, or icons and embed them directly into the document |
| 📤 One-Click Generate & Download | Instantly generate and download your filled document                        |
| 🧩 Supports DOCX & PPTX Templates| Compatible with both Word and PowerPoint templates                          |

---

## 🛠 How to Use

### 1. 📥 Upload Your Template

Upload a `.docx` or `.pptx` file that contains placeholders in the form of `{PLACEHOLDER_NAME}`.

### 2. ✏️ Enter Key Fields

You'll be prompted to enter values for key fields like:
- `{CUSTOMER_NAME}`
- `{CITY_NAME}`
- `{SA_EMAIL}`
- `{COUNTRY}`, etc.

### 3. 📎 Upload Files or Enter Text

For all remaining fields, you can:
- Upload a `.txt`, `.docx`, or `.pptx` → 📃 Extracts text and inserts in place.
- Upload `.xlsx` → 📊 Extracted as a table and inserted into DOCX.
- Upload images (`.jpg`, `.png`) → 🖼️ Embedded directly in place (DOCX only).
- Or enter plain text manually for any placeholder.

### 4. 🧾 Click Generate

Click **🛠 Generate Document**, and your output file will download immediately.

---

## 💡 Tips

- If image upload fails, enter a short description instead (e.g. "Company Logo").
- Keep placeholder names simple, uppercase, and consistent: `{LOGO}`, `{SUMMARY}`, `{DATE}`, etc.
- All placeholders are rendered **in order of appearance** in the document.
- Supports both DOCX and PPTX as input templates (images embed only in DOCX).

---

## 🧪 Example Template

You can try using the provided test template:
👉 [Download CRA_test_template.docx](./CRA_test_template.docx)

---

## 📦 Installation (Local)

```bash
git clone https://github.com/your-username/docfactory.git
cd docfactory
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
./runlocal.sh

🐳 Docker Usage
Build and run using Docker:
docker build -t docfactory .
docker run -p 8000:8000 docfactory

📁 Project Structure

docfactory/
├── app.py
├── runlocal.sh
├── templates/
│   └── index.html
├── static/
│   └── style.css
├── utils/
│   ├── extract_placeholders.py
│   └── docx_filler.py
├── test/
│   └── CRA_test_template.docx
├── requirements.txt
└── README.md

🧑‍💻 Authors
Doan Steven Tran – @Sherlock2019

📄 License
This project is licensed under the MIT License.
