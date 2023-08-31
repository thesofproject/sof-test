#!/usr/bin/env python3

import sys
import os
# Fred: Add new dependency
import matplotlib.pyplot as plt

# Define lists to store C-State names and percentages
c_states = []
percentages = []

# Check if the input file parameter is provided
if len(sys.argv) != 2:
    print("Usage: python script_name.py input_file.txt")
    sys.exit(1)

input_file = sys.argv[1]

# Read the input file and extract relevant data
with open(input_file, "r") as file:
    lines = file.readlines()

# Iterate through the lines and extract C-State data
for line in lines:
    # When line starts with PC
    if line.strip().startswith("PC"):
        columns = line.strip().split(',')
        c_state = columns[0].strip()
        percentage = float(columns[1].strip())
        c_states.append(c_state)
        percentages.append(percentage)

# Plotting the data
plt.figure(figsize=(10, 6))
plt.bar(c_states, percentages, color='blue')
plt.xlabel('C-State')
plt.ylabel('Residency (%)')
plt.title('Package C-State Residency')
plt.ylim(0, 100)  # Set y-axis limit to percentage values
plt.xticks(rotation=45)
plt.tight_layout()

# Get the directory and base filename of the input file
input_dir = os.path.dirname(input_file)
input_filename = os.path.basename(input_file)

# output_file has same path and same base filename but .png extension
output_file = os.path.join(input_dir, os.path.splitext(input_filename)[0] + '.png')
plt.savefig(output_file)

# Display the plot
#plt.show()
