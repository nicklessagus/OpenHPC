# OpenHPC

Metí en el repo el pdf con la receta para OpenHPC y slurm que se baja desde https://github.com/openhpc/ohpc/wiki/2.X.
También un pdf de una receta de Intel (por si sirve para sacar alguna idea).

Conviene primero mirar el PDF que da detalle de que es cada cosa y, en el apéndice, dice como instalar la documentación que viene ya con la receta (página 33). 

Se tomó ese archivo 'recipe.sh' y se separó en tres, cada uno con una parte del proceso. Están numerados y autocontenidos.
El archivo 'input.local' tiene todos los parámetros de configuración, esta versión está modificada y con comentarios para que se entienda que variales se setean

Basicamente instalando un nodo con un centos 8.3, y configurando una placa de red interna ya se puede empezar.
