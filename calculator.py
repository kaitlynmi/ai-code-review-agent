"""
Calculator module with intentional error handling issues for demo purposes.
This code demonstrates missing error handling that AI code review can detect.
"""

import json


def divide(a, b):
    """
    Division without zero check.
    
    ⚠️ ERROR HANDLING: No check for division by zero
    """
    return a / b  # Will raise ZeroDivisionError if b == 0


def parse_config(text):
    """
    Parse JSON without error handling.
    
    ⚠️ ERROR HANDLING: No try-except for JSON parsing
    """
    return json.loads(text)  # Will raise JSONDecodeError for invalid JSON


def get_item(items, index):
    """
    Access list item without bounds check.
    
    ⚠️ ERROR HANDLING: No check for index out of bounds
    """
    return items[index]  # Will raise IndexError if index >= len(items)


def open_file(path):
    """
    Open file without error handling.
    
    ⚠️ ERROR HANDLING: No handling for file not found or permission errors
    """
    with open(path, 'r') as f:
        return f.read()  # Will raise FileNotFoundError if path doesn't exist


def process_user_input(user_input):
    """
    Process input without validation.
    
    ⚠️ ERROR HANDLING: No input validation
    """
    number = int(user_input)  # Will raise ValueError for non-numeric input
    return number * 2
