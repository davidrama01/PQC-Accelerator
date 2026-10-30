# Plantilla del TFM en LaTeX

Abre `main.tex` como documento principal. La plantilla toma como referencia la organización del TFG de David Rama Jimeno y la adapta al proyecto de verificación HAWK en FPGA. No contiene resultados ni conclusiones inventados y no es una plantilla oficial del centro.

## Primeros pasos

1. Edita `config/datos.tex`: título provisional, máster, centro, director y fecha. El autor y la universidad proceden del TFG; confirma el centro para este TFM.
2. Completa el resumen en español y los acrónimos en `preliminares/`.
3. Redacta los capítulos en `capitulos/`. Las notas «Pendiente» indican qué documentar; elimínalas al completar cada apartado.
4. Guarda las figuras en `imagenes/` y las referencias BibTeX en `bibliografia/referencias.bib`.
5. Sustituye el anexo de ejemplos por los anexos definitivos y elimina la referencia bibliográfica de demostración.

## Compilación

En el editor LaTeX de Codex, abre esta carpeta y selecciona `main.tex`. También puedes subir el contenido de la carpeta a Overleaf y elegir pdfLaTeX como compilador y `main.tex` como documento principal.

En local, con una distribución TeX que incluya latexmk, pdfLaTeX, BibTeX y los paquetes declarados en `config/preambulo.tex`, ejecuta desde esta carpeta:

```powershell
latexmk -pdf main.tex
```

El resultado se guarda en `build/main.pdf`. Para limpiar auxiliares: `latexmk -c main.tex`.

Sin latexmk:

```powershell
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

En ese caso el PDF se genera junto a `main.tex`.

## Formato y organización

A4 vertical, cuerpo de 12 puntos, márgenes laterales de 3 cm y superior e inferior de 2,5 cm, equivalentes a los de la memoria del TFG. Interlineado de 1,5, numeración romana en preliminares y arábiga desde la introducción. Portada académica editable, encabezado de capítulo y pie con autor y página. Índices automáticos de contenido, figuras y tablas; bibliografía numérica IEEE con BibTeX; anexos alfabéticos.

La portada se ha adaptado a una página vertical para la memoria. No reproduce la cubierta extendida del Word. No se trasladan los contenidos técnicos, tutores, fechas ni resultados del TFG al TFM. El logotipo es opcional y está comentado en `preliminares/portada.tex`; usa el archivo autorizado por el centro. Comprueba la normativa vigente de tu máster antes de la entrega.

El anexo incluye ejemplos de ecuaciones, referencias cruzadas, figura, tabla, código y cita bibliográfica. Utiliza etiquetas estables (`ch:`, `sec:`, `fig:`, `tab:`, `eq:`) y `\cref{...}` para mantener las referencias al reorganizar capítulos. Para trabajar por capítulos puedes sustituir los `\input` por `\include` y añadir `\includeonly`, teniendo en cuenta que `\include` fuerza saltos de página.
