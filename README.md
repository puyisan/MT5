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

### Instalación
1. Copia la carpeta `MQL5/Experts/SilverBullet` en `<Carpeta de datos MT5>/MQL5/Experts/`.
2. Compila `SilverBullet.mq5` en MetaEditor (F7).
3. Adjunta el EA a un gráfico de **EURUSD** (cualquier TF; el EA usa `InpExecTF` y `InpSwingTF`).

### Reloj del broker (crítico)
Por defecto: `InpBrokerGMTWinter = 2`, `InpBrokerDST = DST EE.UU.` (GMT+2/+3, cierre de NY = 00:00 servidor).
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

### Notas de backtesting
- Usa "Cada tick basado en ticks reales" para M1.
- Ajusta `InpCommissionPerLot` al tipo de cuenta Equiti (0 si la cuenta no cobra comisión) e `InpMaxSpreadPts`.
- `OnTester()` devuelve `PF * sqrt(trades) * (1 - DD%)` para la optimización personalizada.
