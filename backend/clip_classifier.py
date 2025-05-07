# clip_classifier.py
import io
from PIL import Image
import torch
from transformers import CLIPModel, CLIPProcessor
import torch.nn as nn

CLASS_UPPER = ["casual top", "formal top", "fashion top", "sports top", "winter top"]
CLASS_LOWER = ["casual lower", "formal lower", "fashion lower", "sports lower", "winter lower"]
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

class FashionClassifier(nn.Module):
    def __init__(self, clip_model, num_classes):
        super().__init__()
        self.clip_model = clip_model.vision_model
        self.proj = clip_model.visual_projection
        self.fc1 = nn.Linear(clip_model.config.projection_dim, 1024)
        self.fc2 = nn.Linear(1024, 512)
        self.classifier = nn.Linear(512, num_classes)

    def forward(self, pixel_values):
        vision_outputs = self.clip_model(pixel_values=pixel_values)
        pooled_output = vision_outputs.pooler_output
        image_embeds = self.proj(pooled_output)
        x = self.fc1(image_embeds)
        x = torch.relu(x)
        x = self.fc2(x)
        x = torch.relu(x)
        return self.classifier(x)

def load_clip_upper_model():
    """Load and return the CLIP model and processor"""
    # Define the path to your model weights
    weight_path = "C:/Users/User/Downloads/FitChooseIntegrate/FitChooseIntegrate/backend/CLIP_api/best_Upper_f1.pth"
    clip_model = CLIPModel.from_pretrained("patrickjohncyh/fashion-clip")
    processor = CLIPProcessor.from_pretrained("patrickjohncyh/fashion-clip")

    model = FashionClassifier(clip_model, num_classes=len(CLASS_UPPER))
    model.load_state_dict(torch.load(weight_path, map_location=device))
    model.to(device)
    model.eval()
    
    return model, processor

async def process_clip_upper_classification(task_id: str, image_file, model, processor):
    """Process image classification using CLIP model"""
    try:
        contents = await image_file.read()
        image = Image.open(io.BytesIO(contents)).convert("RGB")
        
        inputs = processor(images=image, return_tensors="pt").to(device)
        
        with torch.no_grad():
            outputs = model(inputs["pixel_values"])
            probs = torch.softmax(outputs, dim=1)
            pred_idx = torch.argmax(probs, dim=1).item()
        
        return task_id, {"label": CLASS_UPPER[pred_idx]}
    except Exception as e:
        return task_id, {"error": str(e)}
    
def load_clip_lower_model():
    """Load and return the CLIP model and processor"""
    # Define the path to your model weights
    weight_path = "C:/Users/User/Downloads/FitChooseIntegrate/FitChooseIntegrate/backend/CLIP_api/best_Upper_f1.pth"
    clip_model = CLIPModel.from_pretrained("patrickjohncyh/fashion-clip")
    processor = CLIPProcessor.from_pretrained("patrickjohncyh/fashion-clip")

    model = FashionClassifier(clip_model, num_classes=len(CLASS_LOWER))
    model.load_state_dict(torch.load(weight_path, map_location=device))
    model.to(device)
    model.eval()
    
    return model, processor

async def process_clip_lower_classification(task_id: str, image_file, model, processor):
    """Process image classification using CLIP model"""
    try:
        contents = await image_file.read()
        image = Image.open(io.BytesIO(contents)).convert("RGB")
        
        inputs = processor(images=image, return_tensors="pt").to(device)
        
        with torch.no_grad():
            outputs = model(inputs["pixel_values"])
            probs = torch.softmax(outputs, dim=1)
            pred_idx = torch.argmax(probs, dim=1).item()
        
        return task_id, {"label": CLASS_LOWER[pred_idx]}
    except Exception as e:
        return task_id, {"error": str(e)}