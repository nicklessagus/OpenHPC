# OpenHPC

Metí en el repo el pdf con la receta para OpenHPC y slurm que se baja desde https://github.com/openhpc/ohpc/wiki/2.X.
También un pdf de una receta de Intel (por si sirve para sacar alguna idea).

Conviene primero mirar el PDF que da detalle de que es cada cosa y, en el apéndice, dice como instalar la documentación que viene ya con la receta (página 33).

Es un archivo .sh que se ejecuta (sigue masomenos el PDF, pero veo que tiene más cosas tocadas) y un input.local que tiene los parámetros de configuración. Subo acá unas versiones un poco modificadas y comentadas con las que estuve probando, leyendo por adentro se entiende bastante. 

Hay otro archivo "pruebas_mias" que fue eso, pruebas varias :P. Lo dejo porque tiene un par de cosas que pueden servir, pero con el oficial alcanza.

Basicamente instalando un nodo con un centos 8.3, y configurando una placa de red interna ya se puede seguir la guia (o ejecutar la receta). Unico detalle que recuerdo es que a los nodos hay que ponerle más de un giga de ram, porque sino no le da la memoria para traer la imagen al bootear.
