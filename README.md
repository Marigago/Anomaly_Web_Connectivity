# 🔮 Predicción de Anomalías en Conectividad de México (OONI)  
### **Modelos LSTM y CNN para pronóstico minuto a minuto en series altamente irregulares**

Este proyecto desarrolla un pipeline completo —desde la obtención y limpieza de datos hasta la construcción de modelos de Deep Learning— para **predecir anomalías por minuto en redes mexicanas**, utilizando datos reales provenientes de OONI Web Connectivity.

La serie presenta comportamiento **altamente volátil, no estacionario y explosivo**, con valores que oscilan entre **1 y 4624 anomalías por minuto**, reflejando fallas abruptas en conectividad que son difíciles de anticipar.  
Aquí demostramos cómo transformar este caos en un sistema predictivo funcional.

---

# 🟣 1) Introducción  

## **¿Qué serie se eligió? ¿Por qué es relevante?**

La variable objetivo seleccionada es:

### 👉 **`anomalias_por_minuto`**

Esta métrica resume, para cada minuto, cuántas verificaciones de conectividad resultaron en fallas o comportamientos anómalos.  
Fue elegida porque:

- captura directamente el estado operativo de la red,  
- reacciona rápidamente ante problemas reales,  
- mostró las **mejores correlaciones internas** con el resto de características derivadas,  
- condensa el impacto de fallas DNS/HTTP/TCP y picos de latencia.

La serie es extremadamente relevante para:

- **monitoreo en tiempo real**,  
- **detección temprana de fallas críticas**,  
- **anticipación de interrupciones** en servicios dependientes de Internet,  
- **investigación de condiciones anómalas** en infraestructura de red.

## **Motivación del estudio**

OONI reporta comportamientos de red que pueden pasar de condiciones normales a anomalías extremas en cuestión de segundos.  
Los operadores suelen reaccionar *después* de que ocurre el problema. Aquí buscamos lo contrario:

> **predecir el futuro inmediato (próximos 6 minutos) para actuar antes del colapso.**

La red contiene:

- picos repentinos de miles de anomalías,  
- latencias atípicas (hasta 19,000 s),  
- fallas explosivas en TCP/HTTP,  
- comportamiento irregular imposible de seguir manualmente.

El objetivo final es construir un sistema **predictivo y proactivo**, no reactivo.

---

# 🟣 2) Preparación del Dataset  

## **Fuente de datos**

Los datos provienen de:

- `download_mx_daily.sh` → descarga diaria de mediciones OONI en formato `.jsonl.gz` dentro de archivos TAR.
- Se transformaron a Parquet para procesamiento eficiente.
- Posteriormente se consolidaron en un CSV final:  
  **`ooni_mx_nov_dic.csv`**, correspondiente a **noviembre–diciembre 2025**.

## **Pipeline de limpieza y estandarización**

1. **Descompresión de archivos TAR**  
2. **Normalización de estructuras JSON**  
3. **Conversión a Parquet** (más rápido, más seguro, reiniciable)  
4. **Filtrado por país (MX)**  
5. **Conversión de fechas, orden temporal y sanitización de campos**  
6. **Extracción de:**
   - dominios desde `test_keys`
   - fallas DNS, HTTP y TCP
   - etiquetas de anomalía
7. **Construcción de variables temporales (hora, minuto, segundo)**  
8. **Eliminación de outliers únicos y recorte al percentil 99**

### **Gráficas exploratorias: tendencia y estacionalidad**

Se analizaron:

- series de latencia, anomalías y fallas por minuto,  
- conteos por ASN y dominios,  
- descomposición STL (tendencia + estacionalidad),  
- patrones por minuto de hora y hora del día,  
- autocorrelación ACF/PACF,  
- histogramas y boxplots Before vs After.

El EDA reveló:

- ciclos intrahorarios claros,  
- alta irregularidad,  
- picos explosivos,  
- dependencias temporales significativas,  
- y heterogeneidad por proveedor (ASN) y dominio.

Estos hallazgos justifican el uso de modelos temporales avanzados.

---

# 🟣 3) Ingeniería de Características  

Para convertir la serie en un dataset modelable:

## **Escalamiento y estabilización**

- Se aplica **log1p** al objetivo para comprimir outliers.  
- Se usa **MinMaxScaler** entrenado *solo con TRAIN* (sin leakage).

## **Ventana de pronóstico**

- LSTM → ventana de **60 minutos**  
- CNN → ventana de **7 minutos**  

Ambas ventanas representan hipótesis diferentes sobre cómo la red “recuerda” su pasado.

## **Variables adicionales creadas**

- **Lags**: 1, 2, 3, 5, 10, 15, 30, 60 minutos  
- **Rolling means**: 3, 5, 10, 20 minutos  
- **Diferencias**: `anomalia_diff`, `tcp_diff`  
- **Fallas**: DNS, HTTP, TCP por minuto  
- Todos estos elementos capturan memoria, tendencia, dinámica y reactividad del sistema.

El resultado: un dataset robusto, informativo y sin fuga de información.

---

# 🟣 4) Modelado  

Dos modelos fueron construidos, evaluados y comparados:

---

## **4.1) Modelo LSTM — Long Short-Term Memory**

### Arquitectura:

- LSTM (256 unidades)  
- Dropout 5%  
- Densas: 128 → 64 → 32  
- Salida: 1 neurona (escala log1p)

### Justificación:

- Captura dependencias de largo plazo (60 min).  
- Tolera ruido extremo.  
- Adecuado para series no lineales con picos abruptos.

### Entrenamiento:

- 40 épocas  
- Adam 1e-3  
- Pérdida Huber  
- Batch 32  
- Inicialización determinística  
- División temporal 70/15/15

### Métricas:

| Métrica | Valor |
|--------|-------|
| MAE | 110.49 |
| RMSE | 274.16 |
| sMAPE | 1.01 |

Interpretación:  
Buen desempeño en zonas estables; suaviza picos extremos.

---

## **4.2) Modelo CNN — Convolutional Neural Network 1D**

### Arquitectura:

- Conv1D(128)  
- Conv1D(64)  
- Flatten  
- Dense(32)  
- Dense(1)

### Justificación:

- Detecta patrones locales (ventana 7 min).  
- Muy rápida de entrenar.  
- Menos propensa a sobreajuste en series ruidosas.  
- Complementa a la LSTM capturando fluctuaciones inmediatas.

### Entrenamiento:

- 49 épocas  
- Adam 4e-4  
- Huber  
- Batch 32  
- Shift temporal correcto para CNN

### Métricas:

| Métrica | Valor |
|--------|-------|
| MAE | 127.35 |
| RMSE | 282.49 |
| sMAPE | **0.86** |

Interpretación:  
Error absoluto ligeramente mayor que LSTM,  
pero **error porcentual mucho menor** → mejor desempeño relativo en valores pequeños/medios.

---

# 🟣 5) Evaluación  

## **5.1 Gráfica Real vs Predicción**

Se generó una gráfica continua con:

- Train (real)  
- Test (real + pred)  
- Validation (real + pred)

Sin huecos temporales.

Ambos modelos:

- siguen adecuadamente la forma general,  
- son estables,  
- no generan ruido artificial,  
- suavizan picos extremos.

## **5.2 Pronóstico futuro (6 minutos)**

### LSTM:

Valores futuros:

13.29 → 6.81 → 4.75 → 3.88 → 3.48 → 3.29

Patrón: tendencia descendente y estabilización.

### CNN:

Valores futuros:

40.65 → 8.12 → 30.02 → 45.32 → 7.93 → 13.61

Patrón: oscilación reactiva intensa (propia de CNN).

## Comparación final LSTM vs CNN:

| Aspecto | LSTM | CNN |
|---------|------|------|
| Memoria | Alta (60 min) | Baja (7 min) |
| Detecta | Dependencias largas | Patrones locales |
| Manejo de ruido | Bueno | Excelente |
| Predicción de picos | Difícil | Difícil |
| Costo computacional | Alto | Muy bajo |
| sMAPE | 1.01 | **0.86** |

**Conclusión parcial:**  
CNN = mejor proporcionalidad  
LSTM = mejor memoria

---

# 🟣 6) Conclusiones  

- La serie de anomalías es **extremadamente volátil**, con ruido, picos y comportamiento impredecible.  
- A pesar de ello, ambos modelos lograron capturar gran parte de la dinámica interna.  
- **LSTM** reproduce tendencias globales y memoria extensa.  
- **CNN** detecta fluctuaciones locales con precisión proporcional superior.  
- Ningún modelo predice picos extremos — y esto es natural: los picos no siguen patrones claros.  
- La combinación de ambos enfoques sugiere que un futuro **modelo híbrido (CNN-LSTM o Transformer)** sería ideal.  
- El pipeline construido es completo, reproducible y aplicable a sistemas reales de monitoreo.

### **Mensaje final**

El proyecto demuestra que, incluso en sistemas altamente caóticos como la conectividad real de un país, es posible construir modelos predictivos estables y útiles.  
No se trata de predecir lo impredecible, sino de **detectar tendencias, anticipar inestabilidad y apoyar decisiones operativas en tiempo real**.

Este trabajo constituye una base sólida para investigación futura y para la implementación real en sistemas de monitoreo de red.

