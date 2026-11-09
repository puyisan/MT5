# Auditoría — London_Breakout_v2.65.mq5

Revisión estática de las 4084 líneas del EA (sin compilar ni ejecutar en MetaEditor/MT5).
Las referencias `Lxxx` corresponden a `London_Breakout_v2.65.mq5` tal como está en esta carpeta.

**Resumen:** la estructura es buena (horarios en GMT, OCO de stops, checkpoints, presupuesto de
riesgo diario), pero hay 4 fallos críticos que afectan al dinero o al estado del bot en real.
El más grave: la identificación de cierres por comentario no funciona con SL/TP de MT5.

**Prioridad sugerida de corrección:** 1 → 3 → 4 → 2 → 5/6 → 8.

---

## Estado en v2.66

Todas las correcciones están en `London_Breakout_v2.66.mq5` (la v2.65 se conserva sin cambios). Cada
una va en su propio commit en `main`. **No se ha compilado ni probado en MetaEditor/MT5**: compila con F7
y haz un backtest antes de usarla en demo.

| # | Hallazgo | Estado en v2.66 |
|---|---|---|
| 1 | No compila | ✅ Línea eliminada; globales tardíos movidos a la cabecera |
| 2 | Cierres SL/TP sin el tag | ✅ Salidas asociadas a su entrada por `DEAL_POSITION_ID`; BE/SP/SL por precio; recuperación reescrita |
| 3 | Sin gestión tras la ventana | ✅ `ManageCheckpointsBala` en cada tick mientras haya bala |
| 4 | OCO / netting | ✅ `INIT_FAILED` en netting; cancelación de opuestas en cada tick; aviso si se abren ambas |
| 5 | Lotes | ✅ `OrderCalcProfit`; paso de lote del broker; lote < mínimo → no opera |
| 6 | Modo de llenado | ✅ `SetTypeFillingBySymbol` |
| 7 | DST del broker | ✅ Input `ModoDSTBroker`; viernes en `CierreViernesBroker` |
| 8 | Rango | ✅ Velas cerradas por rango de tiempo; se fija tras la sesión; reintento |
| 9 | Límite diario | ✅ Solo deals del EA; input `ReservaDeslizamientoPct` |
| 10 | Entrada y spread | ✅ `OffsetEntradaPips`, `CompensarSpreadBuy`, `MaxSpreadPips`; comprobación de distancia previa |
| 11 | Telegram bloqueante | ✅ Cola en `OnTimer`; desactivado en el probador |
| 12 | Trailing | ✅ `TrailingPasoPips`; stops/freeze level en BE, SP y trailing |
| 13 | Confirmación | ✅ Cuenta desde la vela más reciente |
| 14 | Bala huérfana | ✅ Si una orden se ejecutó, la bala queda en curso |
| 15 | Cierre diario | ✅ Se comprueba y reintenta 10 min antes del reset |
| 16 | `REASON_CLOSE` | ✅ Cerrar terminal o gráfico ya no cancela pendientes |
| 17 | Reporte mensual | ✅ Lee las 19 columnas |
| Bajos | Festivos, código muerto, prefijo del panel, L553, BE | ✅ Viernes Santo US, Black Friday, reset perdido al cambiar de día, `RRL_PNL_`, signo del SL, `BEOffsetPips` |

### Inputs nuevos

| Input | Por defecto | Valor que reproduce v2.65 |
|---|---|---|
| `ReservaDeslizamientoPct` | 0.0 | 0.0 |
| `OffsetEntradaPips` | 1.0 | 1.0 |
| `CompensarSpreadBuy` | **true** | false |
| `MaxSpreadPips` | 0.0 (off) | 0.0 |
| `BEOffsetPips` | 0.0 | 0.0 |
| `TrailingPasoPips` | **5.0** | 0.0 |
| `ModoDSTBroker` | **AUTO** | EUROPA (en el probador AUTO ya aplica EUROPA) |
| `CierreViernesBroker` | 22 | 22 |

Eliminado: `GMT_LondresCierra` (no se usaba). `ValorPuntoPorLote` queda solo como respaldo.

### Cambios de comportamiento a tener en cuenta
- Cuentas **netting**: el EA no arranca.
- Si el lote por riesgo es menor que el mínimo del broker, **no se lanza la bala** (antes se subía al mínimo).
- La BuyStop suma el spread actual (`CompensarSpreadBuy=true`): menos rupturas falsas, entrada algo peor.
- La ventana NY exige el rango **definitivo**, que se fija en el primer tick tras la sesión de Londres.
- El PnL diario, el límite y el objetivo cuentan solo las operaciones de este EA.
- Si una bala no llega a activarse, al cancelarse sus órdenes en el fin de ventana llega el mensaje
  "BALA X CERRADA CANCELADA" (antes no se procesaba).

### Pendiente / no cubierto
- Observaciones de estrategia (SL relativo al rango, rearme tras SL, inicio 09:00 NY): no se tocaron.
- Cierres anticipados del NYSE (3 jul, 24 dic) a las 13:00 NY: no se filtran.
- Brokers cuyo cierre NY cae a las 00:00 o después: el bloque de reset ya fallaba en v2.65 (antes de la
  apertura NY el EA cree estar "después del cierre"); no se ha rediseñado.
- El estado no se guarda en `GlobalVariable`: tras un reinicio se reconstruye desde el historial (ahora sí
  funciona), pero los contadores de checkpoints del CSV (`statCP1`…) del día se pierden.
- Filas del CSV escritas antes de v2.63 (17 columnas) no son compatibles con el reporte mensual.

---

## 🔴 Críticos

### 1. No compila tal como está (L221 / L234)
```mql5
bool   londresIniciadoAlertado = false;
   festivoAlertado         = false;   // L221: asignación global sin tipo → error
...
bool   festivoAlertado   = false;     // L234: declaración real
```
**Fix:** borrar la L221.

### 2. Los cierres por SL/TP no llevan el tag del EA → clasificación y recuperación rotas (L455-490, L1895-1942)
En MT5 el deal de salida generado por SL/TP lleva el comentario del servidor (`[sl 42150.0]`,
`[tp …]`) y `CTrade::PositionClose` lo deja vacío. El tag `_B1_BUY_E1` solo está en los deals
de entrada (verificable en Historial → Deals).

Consecuencias:
- `DetectarCierreEntrada()` devuelve `""` casi siempre y cae al fallback `tp1Done ? "TP" : "SL"`:
  una bala que cierra en BE se cuenta como SL (Telegram, CSV y panel con estadísticas falsas).
- La "recuperación por cierre externo de E1" (L1748) nunca se activa: si el broker cierra E1 en
  TP1 y el precio retrocede antes del siguiente tick, el SL de E2 queda en BE en vez de +50.
- `RecuperarEstadoDesdHistorial()` nunca ve balas terminadas. Escenario: reinicio del VPS durante
  la bala 3 → `balaActual = 0 + 1 = 1` → se gestiona `_B1` (inexistente) → las posiciones de B3
  quedan sin BE ni trailing y `balaEnCurso` nunca vuelve a `false` → no se lanzan más balas ese día.

**Fix:** mapear cada deal OUT a su entrada vía `DEAL_POSITION_ID`, en una sola pasada:
```mql5
// 1ª pasada: position_id → comentario del deal de ENTRADA
ulong  posIds[]; string posCmt[];
for(int i = 0; i < total; i++)
{
   ulong d = HistoryDealGetTicket(i);
   if(HistoryDealGetInteger(d, DEAL_MAGIC) != MagicNumber) continue;
   if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
   int n = ArraySize(posIds);
   ArrayResize(posIds, n+1); ArrayResize(posCmt, n+1);
   posIds[n] = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
   posCmt[n] = HistoryDealGetString(d, DEAL_COMMENT);
}
// 2ª pasada: en cada deal OUT, buscar su DEAL_POSITION_ID en posIds[] y usar posCmt[]
```
Clasificar BE/SP/SL comparando precio de cierre con precio de apertura (con tolerancia), no con
`profit == 0` (L1935). Para reinicios robustos, persistir el estado (bala actual, checkpoints)
con `GlobalVariableSet` usando una clave fecha+magic.

### 3. Sin gestión de posiciones entre el fin de ventana y el cierre (L1071-1097)
`ManageCheckpointsBala()` solo se llama dentro de `nyOpen ≤ now < cancelTime`, pero las
posiciones viven hasta `closeTime`. Con los valores por defecto (ventana 09:00-13:00 NY, cierre
16:00 NY) hay hasta 3 h sin BE, sin SP tras TP1 y sin trailing. Con `RemoveTP2atCP4=true` el
trailing se congela.

**Fix:** sacar la gestión del bloque de ventana (después del reset y antes de `CanTradeToday`):
```mql5
if(balaEnCurso && balaActual > 0)
   ManageCheckpointsBala(balaActual - 1);   // siempre, haya o no ventana abierta
```

### 4. OCO dependiente solo de `OnTradeTransaction` y sin comprobación de cuenta hedging
- Si se pierde el evento (reconexión, reinicio entre el fill y el handler) las stops opuestas
  siguen vivas: si el precio gira se abren ambas direcciones y `ManageCheckpointsBala` mezcla
  tickets BUY y SELL bajo el mismo tag E1/E2.
- En cuenta **netting** E1 y E2 se fusionan en una sola posición con un único SL/TP y toda la
  lógica de dos entradas se rompe.

**Fix:**
```mql5
// OnInit
if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
{ Print("Este EA requiere cuenta HEDGING"); return INIT_FAILED; }

// ManageCheckpointsBala, tras el bucle de posiciones (red de seguridad):
if(balas[idx].direction != 0)
   CancelOrdenesOpuestas(TradeComment + tag, balas[idx].direction);
```
Asignar `direction` también desde E2, no solo desde E1 (L1609).

---

## 🟠 Altos

### 5. Cálculo de lotes frágil (L2111-2142, L737-740)
- `ValorPuntoPorLote` es manual y su comentario dice "por punto" mientras la fórmula lo usa
  "por pip" (`_Point × PuntosPerPip`). Si se cambia `PuntosPerPip` sin ajustarlo, el riesgo
  real se multiplica ×10 o ×100.
- L740: con paso de lote del broker 0.1 y `LoteMinBroker=0.01`, el paso se fuerza a 0.01 →
  volúmenes como 0.37 → rechazo `INVALID_VOLUME`.
- `MathMax(symMinLot, …)` sube al lote mínimo aunque supere el riesgo (en cuentas pequeñas un
  0.25 % puede convertirse en un 2 %).
- Con datos inválidos devuelve `symMinLot` en vez de 0, así que la comprobación `lots <= 0`
  (L1391) nunca salta.

**Fix:**
```mql5
double CalculateLots(double slDistance, double riskPct)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * riskPct / 100.0;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK), pnl = 0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, price, price - slDistance, pnl) || pnl >= 0)
      return 0;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lots = MathFloor(riskMoney / (-pnl) / step) * step;
   if(lots < vmin) return 0;                       // no forzar el mínimo
   int vd = (int)MathMax(0, MathCeil(-MathLog10(step)));
   return NormalizeDouble(MathMin(lots, vmax), vd);
}
```

### 6. Modo de llenado no configurado
`CTrade` usa FOK por defecto; muchos brokers de CFDs de índices solo aceptan IOC/Return
(error 10030). **Fix:** `trade.SetTypeFillingBySymbol(_Symbol);` en `OnInit`.

### 7. DST del broker asumido europeo (L335-341)
Muchos brokers GMT+2/+3 cambian con el DST de EE. UU. (para que 17:00 NY = 00:00 servidor).
Durante ~3 semanas al año (marzo y fin de octubre/inicio de noviembre) el rango y la ventana se
desplazan 1 h. El cierre de viernes a las 22:00 está hardcodeado (L987) y depende del broker.
**Fix:** en real, offset en vivo `(TimeTradeServer() - TimeGMT()) / 3600`; para el tester, un input
`ENUM {DST_EU, DST_US, SIN_DST}`.

### 8. Rango: última vela incompleta y sin reintento (L1521-1569, L764-781)
- `CopyRates` devuelve `[0]` = vela más antigua. El "Filtro 3" (L1556) descarta la más antigua e
  incluye la vela en formación. El rango se fija en el minuto `londonEnd` con la vela de las
  15:59 recién abierta: se pierde casi todo el último minuto de Londres.
- Si `CopyRates` falla en `OnInit` (historial M1 no sincronizado), `rangeSet` queda en `false` y
  ese día no se opera: no hay reintento.

**Fix:** fijar el rango en el primer tick con `nowMin > londonEnd`, recorriendo solo velas
cerradas (`i ≤ bars-2`), y reintentar en `OnTick` mientras `!rangeFijado && nowMin > londonEnd`.

### 9. El límite diario usa el balance de toda la cuenta (L625-692)
`balance − balanceInicioDia` incluye otros EAs, depósitos y retiros. El deslizamiento del SL en
la apertura de NY puede llevar la pérdida por encima del 2 %. **Fix:** sumar solo deals del magic
y reservar un margen de seguridad para el deslizamiento.

---

## 🟡 Medios

| # | Línea | Problema | Fix |
|---|---|---|---|
| 10 | L1402 | Entrada a solo 1 pip del rango. La BuyStop se ejecuta con el **Ask**: con 2-3 pts de spread la ruptura salta antes de que el Bid rompa, y si el Ask ya supera la entrada la orden se rechaza. El filtro de spread compara contra el SL (50) y nunca actúa. | Offset ≥ spread + stops level; input de spread máximo. |
| 11 | L2664 | `WebRequest` síncrono (timeout 3 s) dentro de `OnTick`; al cerrar una bala se envían 3 mensajes → hasta ~9 s de bloqueo. | Omitir si `MQLInfoInteger(MQL_TESTER)`; cola enviada desde `OnTimer`. |
| 12 | L2079 | El trailing hace `PositionModify` en cada tick que mejora, sin paso mínimo ni comprobación de stops/freeze level. | Modificar solo si mejora ≥ X pts y respeta `STOPS_LEVEL`/`FREEZE_LEVEL`. |
| 13 | L1143 | La confirmación recorre de antigua a reciente y acepta la **primera** racha de N velas aunque las posteriores estén fuera del rango. | Contar desde la vela más reciente hacia atrás. |
| 14 | L1443 | Si se aborta una bala pero una orden ya se ejecutó, la posición queda huérfana y sin gestión (`balaEnCurso=false`). | Tras cancelar, comprobar posiciones con el tag y registrarlas. |
| 15 | L1020 | `CloseAllPositions()` no verifica el resultado; si falla, `ResetDaily()` borra el estado con la posición viva. | Reintentar y no resetear mientras queden posiciones. |
| 16 | L928 | `REASON_CLOSE` (reinicio del VPS) cancela pendientes a mitad de sesión; el comentario dice que `REASON_CHARTCLOSE` las preserva pero no está en la lista. | Decidir y documentar; combinar con el punto 2. |
| 17 | L3863-3880 | El reporte mensual lee 17 campos y el CSV tiene 19 (v2.63 añadió SP y BE) → reporte desalineado. | Leer `bSP` y `bBE` en su posición. |

---

## ⚪ Bajos
- **Festivos:** falta Good Friday en la lista de EE. UU. (solo cubierto si `FiltrarFestivosUK=true`);
  no se contemplan cierres anticipados (3 jul, 24 dic). El aviso de "mañana Black Friday" usa
  `TimeCurrent()` en vez de la fecha recibida (L2393).
- **Código muerto:**
  - En `OnInit`, `currentDay` se asigna (L758) justo antes de compararlo (L789): el fix de v2.62 nunca se ejecuta.
  - Input sin uso: `GMT_LondresCierra`. Variable sin uso: `e2Abierta`.
  - Funciones sin uso: `MoveToBreakEven`, `DetectarSLEnBala`, `DetectBrokerGMTOffset`.
  - `VentanaViernesPips` está en horas, no en pips, y se ignora en silencio si vale ≥ 4.
  - `#property strict` es de MQL4.
- **Objetos del gráfico:** `PANEL_PREFIX = "RRL_"` abarca también `RRL_NVL_`, `RRL_VLIN_` y
  `RRL_RANGO_`; con `DashVisible=false`, `PanelDestroy()` borra rango y niveles cada minuto.
- **L553:** `MathAbs(sl − open)` ignora el lado: un SL original a −50 se interpreta como "SL en
  beneficio" y marca `cp1Done`.
- **BE** exactamente en el precio de apertura, sin cubrir la comisión.

## Observaciones de estrategia (no son bugs)
- SL fijo (50) aunque el rango de Londres sea de 300+ puntos: valorar SL o filtro relativo al
  rango o al ATR.
- Tras cada SL se rearman ambos lados: en días laterales se pueden acumular 4 balas perdidas (−2 %).
- La ventana empieza a las 09:00 NY, antes de la apertura de contado (09:30): confirmar que es
  intencionado.
- Backtest con "Cada tick basado en ticks reales": gaps de apertura y spreads variables cambian
  mucho el resultado de esta estrategia.
