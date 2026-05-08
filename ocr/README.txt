OCR · Image-to-Text
===================

Open ocr/index.html in any browser. Drop an image. Click Run OCR.

The recognition runs entirely in your browser via tesseract.js. No upload,
no server, no internet. The page is a static HTML file.

Layout:
  ocr/
    index.html               the page
    README.txt               this file
    lib/
      tesseract.min.js       core library
      worker.min.js          web-worker entrypoint
      tesseract-core.wasm.js wasm runtime
    lang-data/
      eng.traineddata        English language pack (default)

Adding more languages
---------------------
Download the relevant .traineddata file from
  https://github.com/tesseract-ocr/tessdata_fast
and drop it in ocr/lang-data/. Then edit ocr/index.html and add an
<option> to the <select id="lang"> element with the 3-letter ISO code
(e.g. "deu" for German, "fra" for French, "spa" for Spanish).

The fast traineddata variants are smaller (~10-20 MB each) and accurate
enough for most clean documents. Use the "best" variants for handwriting
or low-quality scans.

License
-------
tesseract.js: Apache 2.0
language packs: Apache 2.0 (Tesseract project)
