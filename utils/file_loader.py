from pathlib import Path
from typing import Union, List, Dict, Tuple
from enum import Enum

paths = {
    'instructions': "riscv_programs",
    'data': "riscv_data",
    'docs': "docs",
}

class FileType(Enum):
    INSTRUCTION = "instruction"  # .asm,
    DATA = "data"                # .bin
    DOCUMENTATION = "docs"       # .md

class FileLoader:
    @staticmethod
    def list_files(file_source: FileType) -> List[str]:
        """List files in the given source directory based on type"""
        # Get absolute path from project root
        
        if file_source == FileType.INSTRUCTION:
            target_dir = Path(paths['instructions'])
            extensions = ['.asm']
        
        elif file_source == FileType.DATA:
            target_dir = Path(paths['data'])
            extensions = ['.bin']
        
        elif file_source == FileType.DOCUMENTATION:
            target_dir = Path(paths['docs'])
            extensions = ['.md']
        
        else:
            raise ValueError(f"Unknown file source: {file_source}")
        
        if not target_dir.exists():
            print(f"Directory not found: {target_dir}")
            return []
        
        files = [f"{target_dir}/{f.name}" for f in target_dir.iterdir() if f.suffix in extensions]
        print(f"Found {len(files)} files in {target_dir}")
        return files

    @staticmethod
    def detect_type(file_path: str) -> FileType:
        """Detect file type from extension or content"""
        suffix = Path(file_path).suffix.lower()
        
        if suffix in ['.asm']:
            return FileType.INSTRUCTION
        elif suffix in ['.md']:
            return FileType.DOCUMENTATION
        elif suffix in ['.bin']:
            # Could be either - check naming convention
            if 'instr' in file_path.lower() or 'prog' in file_path.lower():
                return FileType.INSTRUCTION
            return FileType.DATA
        
        raise ValueError(f"Unknown file type: {suffix}")
    
    @staticmethod
    def load_instruction(file_path: str) -> str:
        """Load instruction file - returns assembly code string"""
        with open(file_path, 'r') as f:
            return f.read()
    
    @staticmethod
    def load_data(file_path: str) -> List[Dict[str, str]]:
        """Load data file - returns list of {address, value} dicts"""
        with open(file_path, 'rb') as f:
            data = f.read()
        
        rows = []
        for i, byte in enumerate(data):
            rows.append({
                'address': f'0x{i:04X}',
                'value': f'0x{byte:02X}'
            })
        return rows
    
    @staticmethod
    def load_documentation(file_path: str) -> str:
        """Load markdown documentation"""
        with open(file_path, 'r') as f:
            return f.read()
    
    @classmethod
    def load(cls, file_path: str) -> Tuple[FileType, Union[str, List[Dict]]]:
        """Universal loader - returns (type, data)"""
        file_type = cls.detect_type(file_path)
        
        if file_type == FileType.INSTRUCTION:
            data = cls.load_instruction(file_path)
        
        elif file_type == FileType.DATA:
            data = cls.load_data(file_path)
        
        elif file_type == FileType.DOCUMENTATION:
            data = cls.load_documentation(file_path)
        
        return file_type, data
