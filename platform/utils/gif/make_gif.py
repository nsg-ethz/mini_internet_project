import json
import glob
import numpy as np
from PIL import Image   

# Build the image from the matrix data source. 
def make_image(infile, outfile):
    with open(infile, 'r') as fd:
        json_data = json.load(fd)

    # Create a mapping group number -> ID.
    mapping = {}
    for fromg in json_data['connectivity']:
        mapping[int(fromg)] = len(mapping) 

    # Create the RGB matrix
    matrix = np.zeros((len(mapping), len(mapping), 3), dtype=np.uint8)

    # Collect validity and connectivity for evert pair of ASes.
    for fromg in json_data['connectivity']:
        for tog, connectivity in json_data['connectivity'][fromg].items():
            
            f = mapping[int(fromg)]
            t = mapping[int(tog)]

            if connectivity:
                try:
                    if json_data['validity'][fromg][tog]:
                        matrix[f][t] = [0,255,0]
                    else:
                        matrix[f][t] = [255,127,0]

                except:
                        matrix[f][t] = [0,255,0]

            elif not connectivity:
                matrix[f][t] = [255,0,0]
            else:
                print (connectivity)
            
    img = Image.fromarray(matrix, 'RGB')
    img = img.resize((800,800))
    img.save(outfile)

# Build the GIF from the set of images.
def gif(indir):
    frames = [Image.open(image) for image in glob.glob(f"{indir}/*.png")]
    frame_one = frames[0]
    frame_one.save(indir+"/matrix.gif", format="GIF", append_images=frames,
        save_all=True, duration=20, loop=0)

