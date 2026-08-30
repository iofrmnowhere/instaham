Pipeline:
pig -> view type -> segment -> dorsal? -> yes or no
yes -> use py cut off helpers to predict weight -> use base segmentation mask for health cnn
no  -> use base segmentation mask for health cnn

Processes:
picture -> feed to yolo segmentation -> construct pig mask -> cutter pig mask -> calculate 5 features/ 16 features -> weight prediction

TASK:
Revise the ML/ML_implementation_plan.md
We'll be refactoring the python files in ML folder, the pipeline for the app would still remain however the changes would be 
based on the said processes, we would need 5 python files for each process which are segmentation, construction, cutter, 
feature calculation and weight prediction. The old files are in the .old_py_files folder which contains the original 
codes before the updated and merged versions in ML folder. 

Use the files in .old_py_files folder to merge them properly this time based on the 5 processes and include the refactors needed
that would be affected by this change such as references, dependent files and etc. Make sure that the wiring of the models in 
the app gets fixed by this change too. Like the previous one ML_implementation_plan.md, the files will be ported into c++
eventually however the only exception is the cutter file, you'll have to create a dummy file for it, whenever it gets called
it would just return the same image.