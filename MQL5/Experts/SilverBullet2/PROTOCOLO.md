# Silver Bullet 2 (v2.00): protocolo de validación

**Hipótesis.** En EURUSD M5, dentro de las ventanas Silver Bullet, un FVG con vela de desplazamiento **a favor de
la tendencia de H1** (cierre de H1 frente a su EMA 50) tiene esperanza positiva después del spread, **sin** exigir
un barrido de liquidez previo.

Las reglas y los criterios de este documento se fijaron **antes** de ver ningún resultado (10-11-2026).
Si se cambia cualquier regla después de ver un resultado, es una hipótesis nueva: se anota aquí con su fecha
y se valida desde cero en un periodo que no se haya usado.

---

## 1. Reglas (fijas)

| Paso | Regla |
|---|---|
| Ventanas | Londres 03:00-04:00, NY AM 10:00-11:00 y NY PM 14:00-15:00, hora de NY. Sin margen previo. |
| Tendencia | Última vela H1 **cerrada** al cerrar la vela 3 del FVG: cierre > EMA 50 → solo compras; cierre < EMA 50 → solo ventas; igual o sin datos → no se opera. |
| FVG | 3 velas de M5. La vela 3 abre dentro de la ventana. Vela 2 con cuerpo ≥ 1 ATR(14) y ≥ 55 % de su rango. Hueco ≥ máx(0,5 pips; 0,2 ATR; 0,5 × spread). Debe ir en la dirección de la tendencia. |
| Entrada | Orden limitada en el borde cercano del FVG. Caduca al final de la ventana. |
| SL | Detrás de la **vela 1** del FVG + 1 pip (en las ventas, más el spread). |
| TP | Nivel de liquidez intacto más cercano en la dirección de la operación (prioridad ≥ 3: Asia, Londres, NY AM, EQH/EQL, PDH/PDL), 0,3 pips antes; tope 6R; 2R si no hay nivel. |
| Filtros | SL entre 3 y 40 pips; spread ≤ 20 % del SL; R:R ≥ 2. |
| Gestión | Break-even a 1R (+0,5 pips); cierre a las 3 h; cierre forzoso el viernes a las 16:30 NY; 1 operación por ventana; pérdida diaria máx. 2 %. |
| Riesgo | 1 % por operación (lote redondeado hacia abajo; nunca se fuerza el lote mínimo). |

**Qué cambia frente a la v1.13 M5** (`SilverBullet_v111_M5.set`). Todo lo demás es idéntico, para que la comparación
mida solo el efecto de quitar el barrido:

| | v1.13 M5 | v2.00 |
|---|---|---|
| Contexto | Barrido de un nivel de prioridad ≥ 2 (desde 30 min antes) | Tendencia: cierre H1 frente a EMA 50 |
| Dirección del FVG | Contraria al barrido | A favor de la tendencia |
| SL | Detrás del extremo del barrido o de la vela 1 (el más lejano) + 1 pip | Detrás de la vela 1 + 1 pip |
| Niveles de liquidez | Señal y objetivo | Solo objetivo del TP |
| Magic / archivos | 20261108-09 / `SilverBullet_*.csv` | **20261111** / `SilverBullet2_*.csv` |

El "SL detrás de la vela 1" puede quedar dentro del rango de la vela 2 cuando esta tiene mecha más allá de la vela 1.
Es la regla elegida; el embudo cuenta cuántas veces pasa (`vela 2 más allá de la vela 1`).

---

## 2. Cómo correr las pruebas

Preset: `MQL5/Profiles/Tester/SilverBullet2_v200_backtest.set` (cópialo a `<Carpeta de datos>/MQL5/Profiles/Tester/`).

| | Diseño | Validación |
|---|---|---|
| Periodo | 2021.01.01 - 2024.12.31 | 2025.01.01 - 2026.11.07 |
| Modelo | 1 minuto OHLC | Cada tick basado en ticks reales |
| Cuándo | Primero | **Una sola vez**, y solo si el diseño pasa |

Comunes: EA `SilverBullet2`, símbolo `EURUSD.sd`, gráfico M5, depósito **20000 USD** (no pips), apalancamiento de la cuenta,
*Parámetros → Restablecer* y luego *Cargar* el preset. Sin optimización: es una sola pasada en cada periodo.

Al terminar cada prueba:
1. Copia `SilverBullet2_operaciones_backtest.csv` de la carpeta `Files` del agente del tester
   (se vacía en la prueba siguiente) como `SB2_diseno.csv` o `SB2_validacion.csv`.
2. Copia el **embudo de señales** de la pestaña *Diario* (bloque `SILVER BULLET 2 - EMBUDO DE SEÑALES`) y la línea `OnTester:`.
3. Calcula el veredicto:
   ```bash
   python3 MQL5/Experts/SilverBullet2/analisis/sb2_stats.py SB2_diseno.csv --fase diseno
   ```
   ```bash
   python3 MQL5/Experts/SilverBullet2/analisis/sb2_stats.py SB2_validacion.csv --fase validacion
   ```

---

## 3. Criterios de aceptación (fijados antes)

**Diseño 2021-2024.** Tienen que cumplirse todos:

| | Criterio | Por qué |
|---|---|---|
| D1 | ≥ 100 operaciones | La v1.13 M5 se quedó en 51 en 6 años: sin muestra no hay conclusión. |
| D2 | Profit factor ≥ 1,20 | Margen sobre el spread de 1,8 pips. |
| D3 | R medio > 0 con t ≥ 2,0 | Que la ventaja no sea ruido (≈ p < 0,05). |
| D4 | IC 95 % bootstrap del R medio > 0 | Igual que D3, sin suponer normalidad. |
| D5 | ≥ 3 de 4 años positivos | Que no dependa de un solo año. |
| D6 | DD máximo de balance ≤ 20 % (riesgo 1 %) | Soportable; la v1.13 llegó al 17 % en 7 años. |

**Validación 2025-2026** (una sola pasada, sin cambiar nada). Tienen que cumplirse todos:

| | Criterio |
|---|---|
| V1 | ≥ 30 operaciones |
| V2 | Profit factor ≥ 1,10 |
| V3 | R medio > 0 |
| V4 | DD máximo de balance ≤ 15 % |

**Decisión.**
- Si el diseño no pasa, la hipótesis se descarta. **No se ajustan parámetros para rescatarla** ni se mira 2025-2026.
- Si el diseño pasa y la validación no, no hay ventaja fuera de muestra. No va a demo.
- Si pasan los dos, se propone una demo en paralelo a la v1.13 (magic 20261111, archivos `SilverBullet2_*.csv`).

---

## 4. Registro de cambios de la hipótesis

| Fecha | Cambio | Motivo |
|---|---|---|
| 10-11-2026 | v2.00: reglas y criterios iniciales | — |
