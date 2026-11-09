# MT5 – Expert Advisors

## Silver Bullet EA (ICT) – `MQL5/Experts/SilverBullet/`

EA para la estrategia **ICT Silver Bullet**: barrido de liquidez (BSL/SSL) → FVG de 3 velas en dirección
contraria al barrido → entrada limitada en el FVG, dentro de la ventana horaria de Nueva York.
Calibrado por defecto para **EURUSD en Equiti (cuenta hedging)**.

```
SilverBullet.mq5            Orquestación (máquina de estados por ventana)
Include/SB_Defines.mqh      Enums y estructuras
Include/SB_NYClock.mqh      Hora servidor <-> UTC <-> NY con DST exacto (EE.UU./Europa)
Include/SB_FVG.mqh          Detector de FVG de 3 velas (sin repintado) + ciclo de vida
Include/SB_Liquidity.mqh    Pools PDH/PDL, Asia, Londres, NY AM, swings, EQH/EQL + barridos
Include/SB_Risk.mqh         Lotaje por % riesgo, spread, pérdida diaria, margen
Include/SB_Executor.mqh     CTrade: órdenes, stops/freeze level, slippage, BE, salida por tiempo
```

**Guía de parámetros:** [`MQL5/Experts/SilverBullet/PARAMETROS.md`](MQL5/Experts/SilverBullet/PARAMETROS.md), qué hace cada parámetro y cómo configurarlo.

### Instalación
1. Copia la carpeta `MQL5/Experts/SilverBullet` en `<Carpeta de datos MT5>/MQL5/Experts/`.
2. Compila `SilverBullet.mq5` en MetaEditor (F7).
3. Adjunta el EA a un gráfico de **EURUSD** (cualquier TF; el EA usa `InpExecTF` y `InpSwingTF`).

### Reloj del broker (crítico)
Por defecto: `InpBrokerGMTWinter = 2`, `InpBrokerDST = DST EE.UU.` (GMT+2/+3, cierre de NY = 00:00 servidor).

**Verificado para Equiti (nov. 2026):** servidor en GMT+2 en invierno y apertura semanal del 26-oct-2026
(semana de desajuste EE.UU./Europa) a las 00:00 → sigue el DST de EE.UU. Los valores por defecto son correctos.
Al iniciar, revisa el log:
- `CNYClock: N aperturas semanales coherentes a las 17:00 NY. Modelo DST OK.` → configuración correcta.
- `[AVISO] ... aperturas semanales no cuadran` → cambia `InpBrokerDST` a `DST Europa` (o el offset) y repite.
- En vivo además se compara el modelo con `TimeTradeServer()-TimeGMT()`.

### Flujo
1. 00:00 NY: se reconstruyen los pools (PDH/PDL, Asia, swings de M5); Londres y NY AM se añaden al cerrar su sesión.
2. Cada vela M1 cerrada: se actualizan los pools y los FVG; un barrido = mecha más allá del nivel + cierre de vuelta en ≤ K velas.
3. En la ventana (o `InpSweepLeadMin` antes): barrido BSL → se busca un FVG bajista (venta); barrido SSL → un FVG alcista (compra).
4. SL detrás del extremo del barrido; TP en el pool opuesto (draw on liquidity) con R:R mínimo, o un R:R fijo si no hay pool.
5. La orden limitada caduca al final de la ventana. 1 operación por ventana. Break-even a 1R y cierre por tiempo máximo.

### Filtros de calidad
- `InpMinSweepPrio` (por defecto **2**): solo abren contexto los barridos de pools relevantes
  (EQH/EQL y sesiones = 3, Londres = 4, PDH/PDL = 5). Los swings simples de M5 (prioridad 1) se ignoran.
- `InpBiasMode` (por defecto **BIAS_OFF**): `BIAS_EMA` (cierre H1 vs EMA 50) o `BIAS_PD_RANGE`
  (premium/discount vs rango del día anterior). La EMA contradice la lógica de reversión: un barrido de BSL
  llega tras una subida que deja el precio sobre la EMA y bloquea la venta.
- `InpNoNewOrderLastMin` (por defecto **0** = off): sin órdenes nuevas en los últimos N minutos de la ventana.

### Cierre forzoso del viernes (v1.06)
- `InpFridayCloseHourNY=16`, `InpFridayCloseMinNY=30`: el viernes a las 16:30 NY se cierran las posiciones del EA,
  se cancelan las pendientes y no se abren nuevas. Evita que el cierre por tiempo no llegue a ejecutarse antes del
  cierre semanal (prueba D: una venta del viernes 22-05-2026 en la ventana PM quedó abierta el fin de semana y el
  gap del lunes la cerró en -275 USD, 2,9R).

### Resultados de referencia (EURUSD.sd Equiti, 01-01-2026 a 07-11-2026, ticks reales, ventana 10-11 NY)
| Prueba | Configuración | Trades | Neto USD | DD equity |
|---|---|---|---|---|
| A | `InpMinSweepPrio=1`, sin sesgo (≈ v1.03) | 16 | +507 | 2,62 % |
| B | prio 2 + `BIAS_EMA` + últimos 10 min | 1 | +24 | 0,32 % |
| **C** | **prio 2, sin sesgo (defaults v1.05)** | **6** | **+1091** | **0,81 %** |
| D | C + ventanas Londres y PM | 9 | +870 | 2,50 % (gap de fin de semana, corregido en v1.06) |

Validación fuera de muestra (2025, modelo "1 minuto OHLC", que reproduce los ticks reales en 2026: +1093 vs +1091):

| Prueba | Configuración | Trades | Neto USD | DD equity |
|---|---|---|---|---|
| F | v1.06, solo AM, jun-dic 2025 | 6 | +455 (pips) | 1,14 % |
| **G** | **v1.06, 3 ventanas, 06-01 a 31-12-2025 (= defaults v1.07)** | **23** | **+711** | **2,86 %** |

Por ventana (2025 / 2026): Londres +458 / +167 · AM −26 / +1077 · PM +279 / −374 (incl. gap).
Ninguna ventana gana todos los años; las tres juntas son positivas en ambos. Por eso v1.07 activa las tres.

Muestra pequeña y elegida dentro de la propia muestra: pendiente de validar fuera de muestra (2025) y en demo.

### Puesta en demo (v1.07)
- El terminal debe estar activo a las 10:00, 17:00 y 21:00 del servidor (VPS o PC 24 h).
- Adjunta el EA a un gráfico de EURUSD.sd, activa *Trading algorítmico* y verifica en *Expertos*:
  `SilverBullet v1.07 iniciado` y `offset broker +2.0h coherente con el modelo`.
- Compara cada semana las operaciones de demo con un backtest de esa misma semana (fills y slippage).

### Prueba de robustez (v1.08)
Presets en `MQL5/Profiles/Tester/` (cópialos a `<Carpeta de datos>/MQL5/Profiles/Tester/`):
- `SilverBullet_v108_default.set`: valores por defecto.
- `SilverBullet_v108_robustez.set`: rejilla 3 x 3 x 3 = 27 pasadas sobre
  `InpMaxHoldMin` (120/180/240), `InpMaxSpreadSLPct` (15/20/25) e `InpDispATR` (0,8/1,0/1,2).

En el tester: pestaña *Parámetros* → clic derecho → **Cargar** el `.set`; *Optimización*: **Algoritmo completo**,
criterio **Personalizado máximo**. Periodo 2025-01-01 a 2026-11-07, ticks reales, 19000 USD.
Exporta los resultados (pestaña *Optimización* → clic derecho → *Exportar a XML*).

Cómo leerlo: **no buscamos la mejor pasada**, sino que la mayoría sea positiva y que los vecinos del valor por
defecto den resultados parecidos. Si solo funcionan los valores actuales, la estrategia está sobreajustada.

`OnTester()` = PF (acotado a 10; sin pérdidas MT5 reporta PF 0) × √operaciones × (1 − DD%/100). Devuelve 0 con
menos de `InpTesterMinTrades` (10) operaciones.

### Registro de operaciones (v1.09, v1.10)
El EA escribe una línea por posición cerrada en `MQL5/Files/SilverBullet_operaciones.csv`
(en el tester: `SilverBullet_operaciones_backtest.csv`, que se vacía en cada prueba; nunca en optimización).
La ruta completa aparece al iniciar, en la pestaña *Expertos* (`Registro de operaciones: ...`).

Columnas: `ticket, abierta, cerrada, dir, ventana, nivel, lotes, entrada_pedida, entrada, sl_inicial, tp_inicial,
salida_pedida, salida_precio, salida, usd, r, slip_entrada_pts, slip_salida_pts, balance, version`.
- `salida`: `TP`, `SL`, `BE`, `tiempo`, `viernes`, `manual`, `stop out`.
- `slip_*_pts`: diferencia en puntos entre el precio pedido y el ejecutado; **positivo = peor** de lo pedido.
- `r`: resultado / distancia entre la entrada pedida y el SL inicial.
- v1.10: en los cierres por tiempo y de viernes, `salida_pedida` es el precio de mercado al enviar el cierre.

Panel de seguimiento: lee en directo desde Google Drive (Google Drive para escritorio sincroniza
`MQL5/Files` y la carpeta `Files` del agente del tester) y empareja demo y backtest por fecha, ventana y dirección.

En MT5 para Mac (Wine) la carpeta está en
`~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files/`
(o en la carpeta de datos que abre *Archivo → Abrir carpeta de datos*).

### Protección y avisos (v1.11)
- **Freno de emergencia** `InpMaxDDStopPct` (8 %): si el equity cae ese % desde su máximo, cancela las pendientes,
  deja de abrir operaciones y avisa. `InpKillClosePositions` cierra también las abiertas (por defecto no: tienen SL).
  En vivo, el pico y el freno se guardan en variables globales del terminal (`SB_<magic>_<cuenta>_pico/_freno`) y
  sobreviven a reinicios. Para reanudar: adjuntar con `InpKillReset=true` y volver a ponerlo en `false`.
- **Notificaciones push** `InpPush`: arranque y parada del EA, orden colocada, entrada, cierre (con USD y R),
  cierre de viernes, freno, errores de ejecución y un resumen diario a las 16:45 NY. Requiere el MetaQuotes ID de la
  app móvil en *Herramientas → Opciones → Notificaciones*.
- **Archivo de estado** `SilverBullet_estado.csv` en `MQL5/Files`, sobrescrito cada 5 min aunque no haya ticks:
  hora (servidor y UTC), estado, ventana, equity, balance, pico, DD, freno, posiciones, pendientes, conexión,
  trading permitido y último error. El panel lo usa para avisar si el EA deja de dar señales.

### Notas de backtesting
- Usa "Cada tick basado en ticks reales" para M1.
- **Depósito en USD, no en pips**: en la pestaña *Configuración* del tester, en el desplegable de divisa junto al
  depósito elige `USD` (no `pips`). En modo pips no se aplica la comisión y el informe no está en dinero.
- `InpCommissionPerLot` = 0 por defecto (cuenta Equiti estándar `.sd`, sin comisión; el coste va en el spread ~1,8 pips). Ponlo en ~7 si usas una cuenta con comisión.
- Spread: `InpMaxSpreadSLPct` (spread máx. como % del SL, por defecto 20%) y `InpMaxSpreadAbsPts` (tope absoluto, 0 = off).
- Si cambias de versión, pulsa "Restablecer" en la pestaña Parámetros del tester: MT5 conserva los valores usados la última vez.
