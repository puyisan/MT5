# Silver Bullet EA: guía de parámetros (v1.12)

Esta guía explica cada parámetro del EA, qué hace, su valor por defecto y cuándo tiene sentido cambiarlo.
Los valores por defecto están calibrados para **EURUSD.sd en Equiti** (cuenta estándar sin comisión, spread
de unos 1,8 pips, servidor GMT+2/+3 con horario de verano de EE. UU.).

> **Unidades.** En EURUSD (5 decimales) **1 pip = 10 puntos**. Todos los parámetros que terminan en `Pts` están
> en puntos. Los que terminan en `ATR` son múltiplos del ATR(14) de su temporalidad, y se adaptan solos a la
> volatilidad.

> **Antes de cambiar nada.** En la prueba de robustez, el 96 % de las combinaciones cercanas a los valores por
> defecto fueron positivas en 2025-2026. Pero el backtest de 2021-2026 dio un profit factor de solo 1,23 y un
> drawdown del 17 %. Si cambias parámetros, hazlo con un motivo y compruébalo en un periodo que no hayas usado
> para elegirlos.

---

## Índice

1. [Cómo funciona el EA, en 6 pasos](#cómo-funciona-el-ea-en-6-pasos)
2. [Reloj del broker](#1-reloj-del-broker)
3. [Ventanas Silver Bullet](#2-ventanas-silver-bullet-hora-de-nueva-york)
4. [Fair Value Gap](#3-fair-value-gap)
5. [Liquidez](#4-liquidez)
6. [Sesgo (bias)](#5-sesgo-bias)
7. [Riesgo](#6-riesgo)
8. [Gestión de la posición](#7-gestión-de-la-posición)
9. [Protección y avisos](#8-protección-y-avisos)
10. [General, optimización y registro](#9-general-optimización-y-registro)
11. [Configuraciones listas para usar](#configuraciones-listas-para-usar)
12. [Errores de configuración frecuentes](#errores-de-configuración-frecuentes)

---

## Cómo funciona el EA, en 6 pasos

Entender el flujo ayuda a saber qué parámetro afecta a cada parte:

1. **Reloj.** Convierte la hora del servidor a la hora de Nueva York, con el cambio de hora correcto → *Reloj del broker*.
2. **Ventana.** Solo busca operaciones en las ventanas de 03:00, 10:00 y 14:00 NY → *Ventanas*.
3. **Barrido.** Espera a que el precio barra un nivel de liquidez relevante (máximo o mínimo del día anterior, de
   Asia, de Londres, máximos o mínimos iguales…) y vuelva a cerrar dentro → *Liquidez*.
4. **FVG.** Tras un barrido de máximos busca un FVG **bajista** (venta); tras uno de mínimos, uno **alcista**
   (compra) → *Fair Value Gap*.
5. **Filtros de riesgo.** Calcula entrada, SL y TP; descarta la operación si el spread pesa demasiado, si el SL
   es muy corto o muy largo o si el R:R no llega; calcula el lote por % de riesgo → *Riesgo*.
6. **Gestión.** Orden limitada en el FVG; break-even a 1R; cierre por tiempo a las 3 h; cierre forzoso el
   viernes; freno de emergencia → *Gestión* y *Protección*.

Al terminar un backtest, el **resumen de señales** de la pestaña *Diario* indica cuántas señales se perdieron en cada
paso. Es la mejor herramienta para entender el efecto de un parámetro.

---

## 1. Reloj del broker

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `InpBrokerGMTWinter` | `2` | Desfase GMT del servidor en **invierno**. |
| `InpBrokerDST` | `DST EE.UU.` | Regla de horario de verano del servidor: `Ninguno`, `EE.UU.` (2.º domingo de marzo → 1.er domingo de noviembre) o `Europa` (último domingo de marzo → último de octubre). |
| `InpValidateHistory` | `true` | Al arrancar, comprueba en el histórico H1 que todas las aperturas semanales caen a las 17:00 NY. Si no cuadran, avisa en *Expertos*. |

**Cuándo cambiarlo:** solo si cambias de broker. **Equiti está verificado** con GMT+2 y horario de verano de
EE. UU. (la apertura del lunes 26-10-2026 fue a las 00:00).

**Cómo verificarlo en otro broker:**
- En vivo, la pestaña *Expertos* debe decir `offset broker +X.Xh coherente con el modelo`.
- En el histórico debe decir `aperturas semanales coherentes a las 17:00 NY`.

Si sale `[AVISO]`, prueba con la otra regla de horario de verano.

> Un reloj mal configurado desplaza todas las ventanas. Durante unas 4 semanas al año el EA operaría a la hora
> equivocada sin que te dieras cuenta.

---

## 2. Ventanas Silver Bullet (hora de Nueva York)

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `InpWinLondon` | `true` | Ventana **03:00-04:00 NY** (10:00-11:00 del servidor de Equiti). |
| `InpWinAM` | `true` | Ventana **10:00-11:00 NY** (17:00-18:00 del servidor). |
| `InpWinPM` | `true` | Ventana **14:00-15:00 NY** (21:00-22:00 del servidor). |
| `InpSweepLeadMin` | `30` | Minutos **antes** de la ventana en los que un barrido ya cuenta (de 09:30 a 10:00 NY para la AM). El FVG sí tiene que formarse dentro de la ventana. |
| `InpMaxBarsSweepToFVG` | `20` | Velas de M1, **contadas solo dentro de la ventana**, que el EA espera un FVG válido tras el barrido. Después, el barrido caduca. |
| `InpNoNewOrderLastMin` | `0` (off) | Si es > 0, no coloca órdenes nuevas en los últimos N minutos de la ventana. |

**Cómo ajustarlo:**
- **Ventanas:** ninguna fue positiva en todos los años; las tres juntas reparten el riesgo. Desactivar una
  reduce el número de operaciones.
- **`InpWinPM`:** la ventana de las 14:00 NY coincide con los comunicados de la **FOMC** (8 al año). Si te
  preocupa el deslizamiento, puedes desactivarla esos días a mano.
- **`InpNoNewOrderLastMin`:** en las pruebas, ponerlo en 10 eliminó la mejor operación del año (+305 USD,
  colocada 3 minutos antes del cierre). Déjalo en 0 salvo que quieras evitar órdenes que casi nunca se ejecutan.
- **`InpMaxBarsSweepToFVG`:** más alto deja pasar FVG más alejados del barrido, menos ligados a él.

---

## 3. Fair Value Gap

Un FVG alcista existe cuando el mínimo de la vela 3 queda por encima del máximo de la vela 1. La vela 2 debe ser
una vela de **desplazamiento** (grande y con mucho cuerpo).

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `InpExecTF` | `M1` | Temporalidad en la que se buscan los FVG y se evalúan los barridos. |
| `InpATRPeriod` | `14` | Periodo del ATR que usan todos los parámetros `…ATR`. |
| `InpMinGapPts` | `5` | Tamaño mínimo del hueco en puntos (0,5 pips). |
| `InpMinGapATR` | `0.20` | Tamaño mínimo del hueco como fracción del ATR. |
| `InpMinGapSpread` | `0.5` | Tamaño mínimo del hueco como múltiplo del spread actual. |
| `InpDispATR` | `1.00` | El **cuerpo** de la vela 2 debe medir al menos 1 ATR. |
| `InpMinBodyRatio` | `0.55` | El cuerpo de la vela 2 debe ser al menos el 55 % de su rango (poca mecha). |
| `InpFVGExpiryBars` | `30` | Velas tras las cuales un FVG se da por caducado (para su estado y su dibujo). |
| `InpEntryMode` | `Borde` | Dónde va la orden limitada: **borde cercano** del FVG (más órdenes ejecutadas) o **CE**, el 50 % del hueco (mejor R:R, más órdenes sin ejecutar). |
| `InpAllowMarketIfInside` | `false` | Si el precio ya está dentro del FVG al confirmarse, entra a mercado en vez de descartar la señal. |

**Cómo ajustarlo:**
- El hueco mínimo aplicado es **el mayor** de los tres criterios (puntos, ATR y spread).
- **`InpMinGapSpread`** estaba en 2 (fijo) en la versión 1.00 y bloqueaba casi todas las señales: con 1,8 pips de spread
  exigía huecos de 3,6 pips en M1. No lo subas mucho.
- **`InpDispATR`:** la rejilla de robustez probó 0,8, 1,0 y 1,2; las tres fueron positivas en 2025-2026. Con 0,8 hay
  más operaciones (unas 40) pero peor profit factor; con 1,2, menos (unas 19) y mejor profit factor.
- **`InpExecTF`:** el EA está pensado para M1. En M5 los FVG son más limpios pero escasos, y habría que ajustar
  todos los parámetros en puntos.

---

## 4. Liquidez

El EA vigila **niveles de liquidez**. Cada uno tiene una **prioridad** que indica su importancia:

| Nivel | Qué es | Prioridad |
|---|---|---|
| PDH / PDL | Máximo y mínimo del día anterior (17:00-17:00 NY) | **5** |
| LonH / LonL | Máximo y mínimo de Londres (02:00-05:00 NY) | **4** |
| AsiaH / AsiaL | Máximo y mínimo de Asia (20:00-00:00 NY) | **3** |
| NYAMH / NYAML | Máximo y mínimo de NY AM (08:30-12:00 NY) | **3** |
| EQH / EQL | Máximos o mínimos **iguales** (dos o más swings al mismo nivel) | **3** |
| SwH / SwL | Swing fractal simple de M5 | **1** (2 si `InpSwingTF` ≥ M15) |

**Barrido válido:** el precio **perfora** el nivel más de `InpMinPenPts`, no se aleja más de `InpMaxPenATR` y
**vuelve a cerrar dentro** en esa vela o en las `InpReclaimBars` siguientes. Si penetra demasiado o no vuelve,
es una **ruptura**: el nivel se da por consumido y no hay señal.

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `InpSwingTF` | `M5` | Temporalidad de los swings (y de los máximos y mínimos iguales). |
| `InpSwingN` | `3` | Fuerza del fractal: velas a cada lado que deben quedar por debajo de un swing alto (o por encima de uno bajo). |
| `InpUseSwingPools` | `true` | Usar swings e iguales. Sin ellos, solo quedan las sesiones y el día anterior. |
| `InpEqTolATR` | `0.10` | Distancia máxima, en ATR de la temporalidad de swings, para considerar "iguales" dos swings. |
| `InpMinPenPts` | `2` | Penetración mínima para contar como barrido (0,2 pips). |
| `InpMaxPenATR` | `3.0` | Penetración máxima, en ATR de M1. Por encima es una ruptura, no un barrido. |
| `InpReclaimBars` | `3` | Velas permitidas para volver a cerrar dentro del nivel. |
| `InpRequireMSS` | `false` | Exigir además un **cambio de estructura** (que una vela cierre más allá del último pivote contrario anterior al barrido). |
| `InpMSSPivotN` | `2` | Fuerza del pivote usado para el MSS. |
| `InpTargetMinPrio` | `3` | Prioridad mínima del nivel **opuesto** que se usa como **TP**. Si no hay ninguno, se usa `InpFallbackRR`. |
| `InpMinSweepPrio` | `2` | **Prioridad mínima del nivel barrido** para abrir contexto. Con 2 se ignoran los swings simples de M5. |

**Cómo ajustarlo:**
- **`InpMinSweepPrio` es el parámetro que más cambió los resultados.** En 2025-2026 los barridos de swings de
  M5 perdían (−392 USD en 11 operaciones) y los de niveles relevantes ganaban (+899 USD en 5). No lo bajes a 1.
- **`InpUseSwingPools = false`** elimina también los **máximos y mínimos iguales**, que fueron de los mejores niveles. No lo
  desactives para "quitar ruido": eso ya lo hace `InpMinSweepPrio`.
- **`InpRequireMSS`:** filtra más, pero reduce aún más el número de operaciones. No mostró mejora en las pruebas.

---

## 5. Sesgo (bias)

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `InpBiasMode` | `Sin filtro` | `EMA`: compras solo si el cierre de H1 está sobre la EMA y ventas solo si está debajo. `Premium/Discount`: compras solo bajo el 50 % del rango del día anterior y ventas solo por encima. |
| `InpBiasTF` | `H1` | Temporalidad de la EMA (solo modo EMA). |
| `InpBiasEMA` | `50` | Periodo de la EMA (solo modo EMA). |

**Cómo ajustarlo:**
- **No uses el modo EMA.** Un barrido de máximos llega tras una subida que deja el precio por encima de la EMA,
  y el filtro bloquea justo la venta que busca el Silver Bullet. En la prueba B eliminó 29 de 43 candidatos y pasó de
  +1091 a +24 USD.
- **`Premium/Discount`** sí encaja con la lógica (barrido de máximos en zona premium → venta), pero no se ha
  validado. Es una de las hipótesis pendientes.

---

## 6. Riesgo

**Cómo se construye cada orden:**

1. **Entrada:** el borde del FVG (o su 50 %, según `InpEntryMode`).
2. **SL:** más allá del extremo del barrido (y de la vela 1 del FVG), más `InpSLBufferPts`. En las ventas se suma
   además el spread, porque el SL se ejecuta en Ask.
3. **Comprobaciones, en este orden:**
   - SL entre `InpMinSLPts` e `InpMaxSLPts`.
   - **Spread ≤ `InpMaxSpreadSLPct` % del SL.**
   - R:R ≥ `InpMinRR`.
4. **TP:** el nivel de liquidez opuesto más cercano con prioridad ≥ `InpTargetMinPrio`, adelantado `InpTPFrontPts`
   y limitado a `InpMaxRR`. Si no hay nivel, se usa `InpFallbackRR`.
5. **Lote:** el que hace que **llegar al SL = `InpRiskPct` % del balance**, calculado con `OrderCalcProfit` (sirve
   para cualquier divisa de cuenta) y redondeado **hacia abajo**. Si queda por debajo del lote mínimo, la operación
   **se descarta**: nunca se fuerza el lote mínimo.

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `InpRiskPct` | `0.5` | % del balance (o del equity) que se pierde si salta el SL. Admite valores de 0 a 5. |
| `InpRiskOnEquity` | `false` | Calcular el riesgo sobre el equity en lugar del balance. |
| `InpMaxDailyLossPct` | `2.0` | Si el resultado del día NY (cerrado + flotante) llega a −2 %, no abre más ese día. `0` = sin límite. |
| `InpCommissionPerLot` | `0` | Comisión de ida y vuelta por lote, en la divisa de la cuenta. Se suma a la pérdida por lote al calcular el lote. **Equiti estándar = 0**; en una cuenta con comisión, unos 7. |
| `InpMaxSpreadSLPct` | `20` | El spread no puede superar el 20 % de la distancia del SL. |
| `InpMaxSpreadAbsPts` | `0` (off) | Tope absoluto de spread en puntos, como seguro adicional. |
| `InpSlippagePts` | `5` | Desviación máxima de precio aceptada en las órdenes **a mercado** (cierres y entradas a mercado). Las órdenes limitadas no deslizan en la entrada. |
| `InpSLBufferPts` | `10` | Margen del SL más allá del extremo del barrido (1 pip). |
| `InpMinSLPts` | `30` | SL mínimo (3 pips). |
| `InpMaxSLPts` | `250` | SL máximo (25 pips). |
| `InpMinRR` | `2.0` | R:R mínimo hasta el TP. |
| `InpMaxRR` | `6.0` | El TP nunca está a más de 6R. |
| `InpFallbackRR` | `2.0` | R:R del TP cuando no hay un nivel de liquidez objetivo. |
| `InpTPFrontPts` | `3` | El TP se coloca 0,3 pips **antes** del nivel objetivo, para asegurar que se ejecute. |

**Cómo ajustarlo:**
- **`InpRiskPct`:** es lo que más define tu experiencia. Con el backtest de 7 años, a riesgo del 1 % el drawdown
  máximo fue del **17 %** y hubo 10 pérdidas seguidas (≈ −10 %). A riesgo del 0,5 %, aproximadamente la mitad. Elige el riesgo
  pensando en el **peor periodo**, no en el promedio.
- **`InpMaxSpreadSLPct`:** es el filtro que más señales descarta (dos de cada tres candidatos), y el que más mejoró
  la calidad: elimina las operaciones con SL muy corto, que el ruido de M1 sacaba en minutos. En las pruebas de
  2026, el profit factor pasó de 0,48 (v1.02, tope fijo, sep-nov) a 1,62 (v1.03, este filtro, ene-nov). Rejilla de robustez:
  - **15 %:** muy pocas operaciones (5-16).
  - **20 %:** el equilibrio.
  - **25 %:** muchas más operaciones (31-60), pero con peor profit factor (1,2-1,6) y drawdown cerca del 5 %.
- **`InpCommissionPerLot`:** ponlo según tu cuenta. Si lo pones donde no hay comisión, el lote sale más pequeño
  de lo debido; si lo omites donde sí la hay, arriesgas más de lo previsto.
- **`InpMinSLPts`:** con un spread de 1,8 pips, el filtro de spread ya exige SL de al menos 9 pips, así que este mínimo casi nunca
  actúa. La idea de subirlo a 12 pips es una hipótesis pendiente de validar.

---

## 7. Gestión de la posición

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `InpBEAtR` | `1.0` | Cuando la operación gana 1R, mueve el SL a la entrada (más el offset). `0` = sin break-even. |
| `InpBEOffsetPts` | `5` | El SL de break-even se coloca 0,5 pips a favor, para cubrir costes. |
| `InpMaxHoldMin` | `180` | Cierra la posición al cumplir 3 horas abierta. `0` = sin límite. |
| `InpFridayCloseHourNY` | `16` | **Viernes:** a las 16:30 NY cierra todo, cancela las pendientes y no abre más. Hora negativa = desactivado. |
| `InpFridayCloseMinNY` | `30` | Minuto del cierre forzoso del viernes. |

**Cómo ajustarlo:**
- **`InpMaxHoldMin` es crítico:** el TP casi nunca se alcanza (8 % de las operaciones en 7 años) y **la mayoría de
  las ganadoras salen por tiempo**. En la rejilla:
  - **120 minutos:** claramente peor (corta las ganadoras).
  - **180 y 240 minutos:** prácticamente iguales.

  180 expone menos tiempo y deja más margen antes del cierre del viernes.
- **Cierre del viernes: no lo desactives.** Sin él, una venta del viernes 22-05-2026 quedó abierta el fin de semana y
  el hueco del lunes la cerró en −275 USD (2,9 veces el riesgo previsto). Con él, esa misma operación terminó en +70.
- **`InpBEAtR`:** convierte en ≈ 0 operaciones que se dan la vuelta (13 de 92 en 7 años). Subirlo a 1,5 deja más
  recorrido pero protege menos.

---

## 8. Protección y avisos

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `InpMaxDDStopPct` | `8.0` | **Freno de emergencia:** si el equity cae un 8 % desde su máximo, cancela las pendientes, **deja de abrir operaciones** y avisa. `0` = desactivado. |
| `InpKillClosePositions` | `false` | Si es `true`, el freno también cierra las posiciones abiertas. Por defecto no, porque ya tienen SL. |
| `InpKillReset` | `false` | Pon `true` **solo una vez**, al adjuntar el EA, para borrar el freno y el pico de equity guardados. Después vuelve a ponerlo en `false`. |
| `InpPush` | `true` | Notificaciones push a la app móvil de MT5. |
| `InpHeartbeatHourNY` | `16` | Hora NY del **resumen diario** por push (lunes a viernes). Hora negativa = desactivado. |
| `InpHeartbeatMinNY` | `45` | Minuto del resumen diario (16:45 NY = 23:45 del servidor). |
| `InpStatusFile` | `SilverBullet_estado.csv` | Archivo de estado (el latido) en `MQL5/Files`, que lee el panel. Vacío = desactivado. |
| `InpStatusEveryMin` | `5` | Cada cuántos minutos se reescribe el archivo de estado. |

**Cómo ajustarlo:**
- **Ajusta `InpMaxDDStopPct` al riesgo:** unas 8 veces `InpRiskPct`. Con riesgo del 1 % → 8 %; con 0,5 % → 4 %.
  El backtest de 7 años llegó al 17 % con riesgo del 1 %: un freno al 8 % **habría parado el EA en 2024**, que es justo
  para lo que existe.
- **El freno sobrevive a reinicios:** el pico y el estado se guardan en variables globales del terminal
  (`SB_<magic>_<cuenta>_pico` y `_freno`). Reiniciar MT5 o el Mac **no** lo desactiva.
- **Notificaciones:** necesitan *Herramientas → Opciones → Notificaciones* activado, con el **MetaQuotes ID** de la app.
  **No se envían en el Strategy Tester.**
- **Si un día laborable no te llega el resumen diario, revisa el Mac:** puede estar suspendido o sin conexión, o MT5 cerrado.

---

## 9. General, optimización y registro

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `InpMagic` | `20261108` | Número que identifica las órdenes de este EA. |
| `InpDraw` | `true` | Dibuja los FVG y los barridos en el gráfico, con una línea de estado. Se desactiva solo en optimización y en backtests no visuales. |
| `InpDrawWindows` | `true` | Dibuja una franja por ventana: azul Londres, naranja AM, violeta PM. Los 30 minutos previos van en un tono más claro, con una línea punteada. Cada franja lleva el nombre y el horario NY, arriba o abajo según dónde haya hueco. Solo es visual: no cambia ninguna señal. Necesita `InpDraw=true`. |
| `InpDrawWinDays` | `5` | Cuántos días hábiles NY se dibujan, incluido hoy (de 1 a 20). Las ventanas de hoy aparecen desde medianoche NY, aunque aún no hayan empezado. |
| `InpVerbose` | `true` | Mensajes detallados en *Expertos*: ventanas, barridos y motivo de cada descarte. Se desactiva solo en optimización. |
| `InpTesterMinTrades` | `10` | En optimización, una pasada con menos operaciones puntúa 0 en el criterio personalizado. |
| `InpJournal` | `true` | Escribe una línea por operación cerrada en el registro CSV. |
| `InpJournalFile` | `SilverBullet_operaciones.csv` | Nombre del registro en `MQL5/Files`. En el tester se añade `_backtest` y se vacía en cada prueba. |
| `InpJournalCommon` | `false` | Guardar el registro y el estado en la carpeta común de todos los terminales (`Common/Files`). |

**Cómo ajustarlo:**
- **`InpMagic`:** usa **un magic distinto por cada copia del EA** que quieras separar. El límite de pérdida diaria
  se cuenta por símbolo y magic; el freno de emergencia, por magic y cuenta.
- **No adjuntes el EA dos veces al mismo símbolo con el mismo magic:** las dos copias se verían como una sola.
- **`InpJournalCommon`:** déjalo en `false` si Google Drive sincroniza la carpeta `MQL5/Files`, como ahora.

---

## Configuraciones listas para usar

Presets en `MQL5/Profiles/Tester/` (*Parámetros → clic derecho → Cargar*).

### Demo en vivo (la actual)
- Valores por defecto, con `InpRiskPct = 1` y `InpMaxDDStopPct = 8`.
- Notificaciones activadas en el terminal; `MQL5/Files` sincronizado con Google Drive.

### Real, primeros meses (si algún día se valida)
- `InpRiskPct = 0.5` e `InpMaxDDStopPct = 4`.
- Lo demás, por defecto.

### Backtest
- *"Cada tick basado en ticks reales"* (o *"1 minuto OHLC"* donde no haya ticks: en este EA da prácticamente lo mismo).
- Depósito en **USD**, no en pips.
- Antes de cada prueba, *Parámetros → clic derecho → **Restablecer***, para no arrastrar valores de pruebas anteriores.
- Al terminar, revisa el **resumen de señales** en *Diario*.

### Optimización (robustez)
- Preset `SilverBullet_v108_robustez.set`.
- *Algoritmo completo* y criterio *Personalizado máximo*.
- Busca que **la mayoría** de las pasadas sean positivas; no te quedes con la mejor.

---

## Errores de configuración frecuentes

| Síntoma | Causa probable | Solución |
|---|---|---|
| El EA no opera nunca | Valores antiguos guardados en el tester | *Parámetros → Restablecer* |
| El resumen dice "spread" en casi todos los rechazos | Cuenta con spread alto frente a SL cortos | Es lo esperado con 1,8 pips; no subas `InpMaxSpreadSLPct` sin probarlo |
| El informe dice `Currency: profit in pips` | El tester está calculando en pips | Pestaña *Configuración* → divisa del depósito **USD** |
| Las ventanas se abren a una hora rara | Reloj del broker mal configurado | Revisa `InpBrokerGMTWinter` e `InpBrokerDST` y el aviso `CNYClock` |
| No llegan notificaciones | Terminal sin MetaQuotes ID, o es un backtest | *Herramientas → Opciones → Notificaciones → Probar* |
| El EA no abre operaciones y dice "freno de emergencia activo" | Se alcanzó el drawdown máximo (o quedó activo de una sesión anterior) | Revisa qué pasó; para reanudar, adjunta una vez con `InpKillReset = true` |
| Lote más pequeño de lo esperado | `InpCommissionPerLot` > 0 en una cuenta sin comisión | Ponlo en 0 |
| Operación descartada por "lote < mínimo" | Balance pequeño frente a un SL largo | Es correcto: el EA nunca supera el riesgo forzando el lote mínimo |
