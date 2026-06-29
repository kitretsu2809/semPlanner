import os
import urllib.request
from PIL import Image, ImageDraw, ImageFont, ImageFilter

def download_font():
    pass # Use system fonts instead

def draw_text(draw, text, position, font, max_width, fill="white"):
    lines = []
    words = text.split()
    current_line = []
    for word in words:
        current_line.append(word)
        # Check size
        bbox = draw.textbbox((0, 0), " ".join(current_line), font=font)
        if bbox[2] > max_width:
            current_line.pop()
            lines.append(" ".join(current_line))
            current_line = [word]
    if current_line:
        lines.append(" ".join(current_line))
    
    y = position[1]
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        draw.text((position[0], y), line, font=font, fill=fill)
        y += (bbox[3] - bbox[1]) + 10
    return y

def make_carousel(screenshots):
    download_font()
    bold_font_large = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 72)
    bold_font_med = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 54)
    reg_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 40)
    
    out_dir = "INSTAGRAM_ADS"
    os.makedirs(out_dir, exist_ok=True)
    
    slides = [
        {
            "headline": "Got a messy timetable?",
            "subtext": "Upload messy timetables, syllabi & meal times.",
            "img": screenshots[0],
            "bg": (0, 30, 80)
        },
        {
            "headline": "Set your end goal.",
            "subtext": "Want a Backend Internship? We map it out.",
            "img": screenshots[1] if len(screenshots) > 1 else screenshots[0],
            "bg": (0, 122, 255)
        },
        {
            "headline": "Your goals, our schedule.",
            "subtext": "semPlanner finds the gaps to make it happen.",
            "img": screenshots[2] if len(screenshots) > 2 else screenshots[0],
            "bg": (20, 20, 20)
        }
    ]
    
    for i, slide in enumerate(slides):
        img = Image.new('RGB', (1080, 1080), color=slide["bg"])
        draw = ImageDraw.Draw(img)
        
        # Add text
        y = draw_text(draw, slide["headline"], (80, 100), bold_font_large, 920, fill="white")
        draw_text(draw, slide["subtext"], (80, y + 20), reg_font, 920, fill=(200, 220, 255))
        
        # Add screenshot
        try:
            ss = Image.open(slide["img"])
            # Resize screenshot to fit nicely (e.g., width 600)
            target_width = 650
            ratio = target_width / float(ss.size[0])
            target_height = int((float(ss.size[1]) * float(ratio)))
            ss = ss.resize((target_width, target_height), Image.Resampling.LANCZOS)
            
            # Mask for rounded corners
            mask = Image.new("L", ss.size, 0)
            draw_mask = ImageDraw.Draw(mask)
            draw_mask.rounded_rectangle([(0, 0), ss.size], radius=30, fill=255)
            
            # Paste screenshot
            x_offset = int((1080 - target_width) / 2)
            y_offset = 400
            
            # Draw shadow
            shadow = Image.new("RGBA", (1080, 1080), (0,0,0,0))
            shadow_draw = ImageDraw.Draw(shadow)
            shadow_draw.rounded_rectangle([(x_offset-10, y_offset-10), (x_offset+target_width+10, y_offset+target_height+10)], radius=40, fill=(0,0,0,100))
            shadow = shadow.filter(ImageFilter.GaussianBlur(15))
            img.paste(shadow, (0,0), shadow)
            
            img.paste(ss, (x_offset, y_offset), mask)
            
        except Exception as e:
            print(f"Failed to process screenshot: {e}")
            
        img.save(f"{out_dir}/slide_{i+1}.png")
        print(f"Generated {out_dir}/slide_{i+1}.png")

if __name__ == "__main__":
    folder = "SCREENSHOTS"
    files = [os.path.join(folder, f) for f in os.listdir(folder) if f.endswith(('.png', '.jpg', '.jpeg'))]
    files.sort()
    make_carousel(files)
