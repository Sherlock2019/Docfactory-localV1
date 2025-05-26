from pptx import Presentation

def generate_filled_pptx(template_path, uploads, output_stream):
    prs = Presentation(template_path)
    for slide in prs.slides:
        for shape in slide.shapes:
            if hasattr(shape, "text"):
                for ph, val in uploa
