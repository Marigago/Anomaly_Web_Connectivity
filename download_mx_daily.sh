#!/bin/bash

START=20251028
END=20251130

OUTDIR="raw"
mkdir -p "$OUTDIR"

current=$START

while [[ $current -le $END ]]; do
    echo "📅 Listando $current ..."

    aws s3 --no-sign-request ls \
        s3://ooni-data-eu-fra/raw/$current/ \
        --recursive \
        | grep "/MX/webconnectivity/" \
        | grep ".jsonl.gz" \
        > tmp_list.txt

    count=$(wc -l < tmp_list.txt)
    echo "📦 $count archivos encontrados"

    if [[ $count -gt 0 ]]; then
        echo "⬇️ Descargando $current ..."

        # Extrae SIEMPRE la última columna (la ruta del archivo)
        awk '{print "s3://ooni-data-eu-fra/" $NF}' tmp_list.txt > tmp_paths.txt

        # DESCARGA PARALELA
        cat tmp_paths.txt | xargs -n 1 -P 16 -I {} aws s3 --no-sign-request cp {} "$OUTDIR"/
    fi

    # NEXT DAY
    current=$(date -j -f "%Y%m%d" -v+1d "$current" +"%Y%m%d")
done

rm -f tmp_list.txt tmp_paths.txt
echo "🎉 Finalizado"

#ejemplo de uso: bash download_mx_daily.sh
