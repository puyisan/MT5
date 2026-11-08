//+------------------------------------------------------------------+
//|                                                 SilverBullet.mq5 |
//|  ICT Silver Bullet: barrido de liquidez (BSL/SSL) + FVG de 3     |
//|  velas en contra del barrido, dentro de la ventana horaria NY.   |
//|                                                                  |
//|  Calibrado por defecto para EURUSD en Equiti (cuenta hedging).   |
//|  Toda la lógica de señal corre 1 vez por vela cerrada del TF de  |
//|  ejecución; en cada tick solo se gestiona BE / salida por tiempo.|
//+------------------------------------------------------------------+
#property copyright "puyisan"
#property version   "1.08"
#property description "ICT Silver Bullet - Liquidity sweep + 3-candle FVG (NY time, DST-safe)"

#include "Include\SB_Defines.mqh"
#include "Include\SB_NYClock.mqh"
#include "Include\SB_FVG.mqh"
#include "Include\SB_Liquidity.mqh"
#include "Include\SB_Risk.mqh"
#include "Include\SB_Executor.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Reloj del broker ==="
input int             InpBrokerGMTWinter   = 2;              // Offset GMT del servidor en invierno
input ENUM_BROKER_DST InpBrokerDST         = BROKER_DST_US;  // Regla DST del servidor
input bool            InpValidateHistory   = true;           // Validar DST con aperturas semanales

input group "=== Ventanas Silver Bullet (hora NY) ==="
input bool            InpWinLondon         = true;           // 03:00-04:00 NY (servidor Equiti 10:00)
input bool            InpWinAM             = true;           // 10:00-11:00 NY (servidor Equiti 17:00)
input bool            InpWinPM             = true;           // 14:00-15:00 NY (servidor Equiti 21:00)
input int             InpSweepLeadMin      = 30;             // Minutos previos en que un barrido cuenta
input int             InpMaxBarsSweepToFVG = 20;             // Velas máx. entre barrido y FVG
input int             InpNoNewOrderLastMin = 0;              // Sin órdenes nuevas en los últimos N min de la ventana (0 = off)

input group "=== Fair Value Gap ==="
input ENUM_TIMEFRAMES InpExecTF            = PERIOD_M1;      // TF de ejecución / FVG
input int             InpATRPeriod         = 14;             // Periodo ATR
input double          InpMinGapPts         = 5;              // Tamaño mínimo del gap (puntos)
input double          InpMinGapATR         = 0.20;           // Tamaño mínimo del gap (x ATR)
input double          InpMinGapSpread      = 0.5;            // Tamaño mínimo del gap (x spread)
input double          InpDispATR           = 1.00;           // Cuerpo mínimo de C2 (x ATR)
input double          InpMinBodyRatio      = 0.55;           // Cuerpo/rango mínimo de C2
input int             InpFVGExpiryBars     = 30;             // Caducidad del FVG (velas)
input ENUM_SB_ENTRY   InpEntryMode         = ENTRY_EDGE;     // Punto de entrada
input bool            InpAllowMarketIfInside = false;        // Entrar a mercado si ya está dentro del FVG

input group "=== Liquidez ==="
input ENUM_TIMEFRAMES InpSwingTF           = PERIOD_M5;      // TF de swings
input int             InpSwingN            = 3;              // Fuerza del fractal (velas por lado)
input bool            InpUseSwingPools     = true;           // Usar swings / equal highs-lows
input double          InpEqTolATR          = 0.10;           // Tolerancia equal highs/lows (x ATR swing)
input double          InpMinPenPts         = 2;              // Penetración mínima del barrido (puntos)
input double          InpMaxPenATR         = 3.0;            // Penetración máxima (x ATR ejec.) -> ruptura
input int             InpReclaimBars       = 3;              // Velas para recuperar el nivel
input bool            InpRequireMSS        = false;          // Exigir Market Structure Shift
input int             InpMSSPivotN         = 2;              // Fuerza del pivote para el MSS
input int             InpTargetMinPrio     = 3;              // Prioridad mínima del pool objetivo (1-5)
input int             InpMinSweepPrio      = 2;              // Prioridad mínima del pool barrido (1=swing M5, 3=EQ/sesión, 5=PDH/PDL)

input group "=== Sesgo (bias) ==="
input ENUM_SB_BIAS    InpBiasMode          = BIAS_OFF;       // Filtro de sesgo (EMA anula los setups de reversión; ver README)
input ENUM_TIMEFRAMES InpBiasTF            = PERIOD_H1;      // TF del sesgo (modo EMA)
input int             InpBiasEMA           = 50;             // Periodo EMA del sesgo

input group "=== Riesgo ==="
input double          InpRiskPct           = 0.5;            // Riesgo por operación (% balance)
input bool            InpRiskOnEquity      = false;          // Calcular sobre equity
input double          InpMaxDailyLossPct   = 2.0;            // Pérdida diaria máx. (%), 0 = off
input double          InpCommissionPerLot  = 0.0;            // Comisión ida+vuelta por lote (divisa cuenta). Equiti estándar = 0
input double          InpMaxSpreadSLPct    = 20.0;           // Spread máximo (% de la distancia del SL), 0 = off
input int             InpMaxSpreadAbsPts   = 0;              // Tope absoluto de spread (puntos), 0 = off
input int             InpSlippagePts       = 5;              // Slippage máximo (puntos)
input double          InpSLBufferPts       = 10;             // Margen del SL más allá del barrido (puntos)
input double          InpMinSLPts          = 30;             // SL mínimo (puntos)
input double          InpMaxSLPts          = 250;            // SL máximo (puntos)
input double          InpMinRR             = 2.0;            // R:R mínimo
input double          InpMaxRR             = 6.0;            // R:R máximo (cap del TP)
input double          InpFallbackRR        = 2.0;            // R:R si no hay pool objetivo
input double          InpTPFrontPts        = 3;              // Adelantar TP al pool (puntos)

input group "=== Gestión ==="
input double          InpBEAtR             = 1.0;            // Break-even a X R (0 = off)
input double          InpBEOffsetPts       = 5;              // Offset del BE (puntos)
input int             InpMaxHoldMin        = 180;            // Duración máx. de la posición (min, 0 = off)
input int             InpFridayCloseHourNY = 16;             // Viernes: cierre forzoso, hora NY (<0 = off)
input int             InpFridayCloseMinNY  = 30;             // Viernes: cierre forzoso, minuto NY

input group "=== General ==="
input ulong           InpMagic             = 20261108;       // Magic number
input bool            InpDraw              = true;           // Dibujar FVG / barridos
input bool            InpVerbose           = true;           // Log detallado

input group "=== Optimización ==="
input int             InpTesterMinTrades   = 10;             // Mín. operaciones para puntuar en OnTester (antes 30)

//+------------------------------------------------------------------+
//| Utilidades                                                       |
//+------------------------------------------------------------------+
class CNewBar
  {
private:
   datetime          m_last;
public:
                     CNewBar(void) : m_last(0) {}
   bool              IsNew(const string sym,const ENUM_TIMEFRAMES tf)
     {
      const datetime t=iTime(sym,tf,0);
      if(t==0 || t==m_last) return false;
      m_last=t;
      return true;
     }
  };

//+------------------------------------------------------------------+
//| Globales                                                         |
//+------------------------------------------------------------------+
CNYClock      g_clock;
CFVGDetector  g_fvg;
CLiquidityMap g_liq;
CRiskManager  g_risk;
CExecutor     g_exec;
CNewBar       g_barExec, g_barSwing;

int           g_hAtrExec  = INVALID_HANDLE;
int           g_hAtrSwing = INVALID_HANDLE;
int           g_hBiasMA   = INVALID_HANDLE;
double        g_buf[];
MqlRates      g_rates[];

ENUM_SB_STATE g_state     = SB_IDLE;
int           g_win       = -1;
datetime      g_friCutoff = 0;          // hora servidor del cierre forzoso del viernes (0 = hoy no aplica)
bool          g_friDone   = false;
SSweepEvent   g_sweep;
int           g_sweepBars = 0;
double        g_mssLevel  = 0.0;
bool          g_mssOk     = false;

bool          g_verbose   = true;
bool          g_draw      = false;

//--- embudo de diagnóstico (se imprime al terminar el backtest / quitar el EA)
struct SFunnel
  {
   int               days, windows, sweeps, sweepsReplaced, sweepsIgnored, sweepsExpired;
   int               fvgWin, fvgDirMismatch, fvgBeforeSweep, fvgOutOfWindow, fvgNoMSS, fvgCandidates;
   int               rejExposure, rejSpread, rejSLMin, rejSLMax, rejRR, rejKind, rejDaily, rejLots, rejMargin, rejSend;
   int               rejSpreadAbs, rejSpreadPct;
   int               sweepsLowPrio, fvgBias, rejLate;
   int               placed, filled, expired;
   int               rejFriday, friCloses;
   int               spreadN, spreadMin, spreadMax;
   double            spreadSum;
  };
SFunnel       g_fn;

//+------------------------------------------------------------------+
void Log(const string s) { if(g_verbose) Print(s); }

string StateToString(const ENUM_SB_STATE s)
  {
   switch(s)
     {
      case SB_IDLE:         return "IDLE";
      case SB_SWEPT:        return "SWEPT";
      case SB_ORDER_PLACED: return "ORDER";
      case SB_IN_TRADE:     return "IN_TRADE";
      case SB_DONE:         return "DONE";
     }
   return "?";
  }

bool ReadATR(const int handle,double &val)
  {
   ResetLastError();
   if(CopyBuffer(handle,0,1,1,g_buf)!=1) return false;
   val=g_buf[0];
   return(val>0.0);
  }

//+------------------------------------------------------------------+
//| Dibujo (solo en gráfico / tester visual, nunca en optimización)  |
//+------------------------------------------------------------------+
void DrawFVG(const SFVG &f)
  {
   if(!g_draw) return;
   const string n=StringFormat("%sFVG_%I64d",SB_OBJ_PREFIX,(long)f.tC3);
   const datetime t2=f.tC3+(datetime)(PeriodSeconds(InpExecTF)*InpFVGExpiryBars);
   if(!ObjectCreate(0,n,OBJ_RECTANGLE,0,f.tC1,f.top,t2,f.bottom)) return;
   ObjectSetInteger(0,n,OBJPROP_COLOR,(f.dir>0)?clrSeaGreen:clrIndianRed);
   ObjectSetInteger(0,n,OBJPROP_FILL,true);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
  }

void DrawSweep(const SSweepEvent &e)
  {
   if(!g_draw) return;
   const string n=StringFormat("%sSWP_%I64d_%d",SB_OBJ_PREFIX,(long)e.time,e.side);
   if(!ObjectCreate(0,n,OBJ_ARROW,0,e.breachTime,e.extreme)) return;
   ObjectSetInteger(0,n,OBJPROP_ARROWCODE,(e.side>0)?234:233);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,(e.side>0)?ANCHOR_BOTTOM:ANCHOR_TOP);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clrGold);
   ObjectSetString(0,n,OBJPROP_TEXT,PoolTypeToString(e.type));
  }

void UpdateStatus(void)
  {
   if(!g_draw) return;
   Comment(StringFormat("Silver Bullet | NY %s | ventana %s | estado %s | pools %d",
                        TimeToString(g_clock.ServerToNY(TimeCurrent()),TIME_MINUTES),
                        g_clock.WindowName(g_win),StateToString(g_state),g_liq.Total()));
  }

//+------------------------------------------------------------------+
//| Nivel de MSS: último pivote contrario ANTES del barrido          |
//| BSL barrido (venta) -> último swing low; SSL -> último swing high|
//+------------------------------------------------------------------+
double FindMSSLevel(const SSweepEvent &ev)
  {
   MqlRates r[];
   ArraySetAsSeries(r,false);
   const datetime from=ev.breachTime-PeriodSeconds(InpExecTF);
   const int n=CopyRates(_Symbol,InpExecTF,from,60,r);           // ascendente, termina antes del barrido
   const int k=MathMax(1,InpMSSPivotN);
   for(int i=n-1-k;i>=k;i--)
     {
      bool ok=true;
      for(int j=1;j<=k && ok;j++)
        {
         if(ev.side>0) ok=(r[i-j].low >r[i].low  && r[i+j].low >r[i].low);
         else          ok=(r[i-j].high<r[i].high && r[i+j].high<r[i].high);
        }
      if(ok) return (ev.side>0)?r[i].low:r[i].high;
     }
   return 0.0;
  }

void StartSweep(const SSweepEvent &ev)
  {
   g_fn.sweeps++;
   g_sweep    =ev;
   g_sweepBars=0;
   g_state    =SB_SWEPT;
   g_mssOk    =!InpRequireMSS;
   g_mssLevel =InpRequireMSS?FindMSSLevel(ev):0.0;
   DrawSweep(ev);
   Log(StringFormat("[%s] Barrido %s %s @%.5f (extremo %.5f). Busco FVG %s%s",
                    g_clock.WindowName(g_win),(ev.side>0)?"BSL":"SSL",PoolTypeToString(ev.type),
                    ev.price,ev.extreme,(ev.side>0)?"BAJISTA":"ALCISTA",
                    InpRequireMSS?StringFormat(" (MSS en %.5f)",g_mssLevel):""));
  }

void UpdateMSS(const MqlRates &bar)
  {
   if(g_mssOk || g_mssLevel<=0.0 || bar.time<g_sweep.breachTime) return;
   if((g_sweep.side>0 && bar.close<g_mssLevel) || (g_sweep.side<0 && bar.close>g_mssLevel))
     {
      g_mssOk=true;
      Log(StringFormat("MSS confirmado: cierre %.5f más allá de %.5f",bar.close,g_mssLevel));
     }
  }

//+------------------------------------------------------------------+
void OnWindowChange(const int w)
  {
   if(g_state==SB_ORDER_PLACED && g_exec.HasPending())
     {
      g_exec.CancelPendings();
      g_fn.expired++;
      Log(StringFormat("[%s] Fin de ventana: orden pendiente cancelada",g_clock.WindowName(g_win)));
     }
   g_win      =w;
   g_state    =SB_IDLE;
   g_sweepBars=0;
   g_mssOk    =false;
   g_mssLevel =0.0;
   if(w>=0) g_fn.windows++;
   if(w>=0)
      Log(StringFormat("[%s] Ventana activa (servidor %s - %s)",g_clock.WindowName(w),
                       TimeToString(g_clock.WindowStart(w),TIME_MINUTES),
                       TimeToString(g_clock.WindowEnd(w),TIME_MINUTES)));
  }

//+------------------------------------------------------------------+
//| Construcción y envío de la orden con todos los filtros de riesgo |
//+------------------------------------------------------------------+
void TryEnter(const int w,const SFVG &f)
  {
   if(g_friCutoff>0 && TimeCurrent()>=g_friCutoff)
     { g_fn.rejFriday++; Log("Entrada descartada: pasado el cierre forzoso del viernes"); return; }
   if(g_exec.HasPosition() || g_exec.HasPending())
     { g_fn.rejExposure++; Log("Entrada descartada: ya hay exposición del EA"); return; }

   int spreadPts=0;
   const bool absOk=g_risk.SpreadOK(spreadPts);
   g_fn.spreadN++; g_fn.spreadSum+=spreadPts;
   if(g_fn.spreadN==1 || spreadPts<g_fn.spreadMin) g_fn.spreadMin=spreadPts;
   if(spreadPts>g_fn.spreadMax) g_fn.spreadMax=spreadPts;
   if(!absOk)
     { g_fn.rejSpread++; g_fn.rejSpreadAbs++;
       Log(StringFormat("Entrada descartada: spread %d > tope absoluto %d pts",spreadPts,InpMaxSpreadAbsPts)); return; }
   const double spread=spreadPts*_Point;
   const int    dir   =f.dir;

   //--- entrada, SL detrás del barrido (y de C1)
   double entry=(InpEntryMode==ENTRY_CE)?f.ce:((dir>0)?f.top:f.bottom);
   const double ext=(dir>0)?MathMin(g_sweep.extreme,f.c1Extreme):MathMax(g_sweep.extreme,f.c1Extreme);
   double sl=(dir>0)?ext-InpSLBufferPts*_Point:ext+InpSLBufferPts*_Point+spread;   // venta: SL se ejecuta en Ask
   entry=g_exec.NormPrice(entry);
   sl   =g_exec.NormPrice(sl);

   double risk=MathAbs(entry-sl);
   if(risk/_Point<InpMinSLPts || risk/_Point>InpMaxSLPts)
     { if(risk/_Point<InpMinSLPts) g_fn.rejSLMin++; else g_fn.rejSLMax++;
       Log(StringFormat("Entrada descartada: SL %.0f pts fuera de [%.0f, %.0f]",risk/_Point,InpMinSLPts,InpMaxSLPts)); return; }

   //--- spread relativo al stop: lo que realmente importa es su peso sobre el riesgo
   const double spreadPct=100.0*spread/risk;
   if(InpMaxSpreadSLPct>0.0 && spreadPct>InpMaxSpreadSLPct)
     { g_fn.rejSpread++; g_fn.rejSpreadPct++;
       Log(StringFormat("Entrada descartada: spread %d pts = %.1f%% del SL (%.0f pts) > %.1f%%",
                        spreadPts,spreadPct,risk/_Point,InpMaxSpreadSLPct)); return; }

   //--- TP: draw on liquidity (pool opuesto) o RR fijo
   double target=0.0, tp=0.0;
   const bool hasTarget=g_liq.NearestTarget(dir,entry,InpTargetMinPrio,target);
   if(hasTarget) tp=(dir>0)?target-InpTPFrontPts*_Point:target+InpTPFrontPts*_Point+spread;
   else          tp=entry+dir*InpFallbackRR*risk;
   if(dir*(tp-entry)>InpMaxRR*risk) tp=entry+dir*InpMaxRR*risk;
   tp=g_exec.NormPrice(tp);

   double rr=dir*(tp-entry)/risk;
   if(rr<InpMinRR)
     { g_fn.rejRR++; Log(StringFormat("Entrada descartada: R:R %.2f < %.2f (objetivo %s)",rr,InpMinRR,hasTarget?"pool":"fijo")); return; }

   //--- tipo de orden
   const ENUM_SB_ORDER_KIND kind=g_exec.Decide(dir,entry,sl,tp,InpAllowMarketIfInside);
   if(kind==KIND_INVALID)
     { g_fn.rejKind++; Log("Entrada descartada: precio/distancias no válidas para la orden (stops/freeze level)"); return; }
   double effEntry=entry;
   if(kind==KIND_MARKET)
     {
      effEntry=g_exec.MarketPrice(dir);
      risk=MathAbs(effEntry-sl);
      rr  =dir*(tp-effEntry)/risk;
      if(rr<InpMinRR || risk/_Point>InpMaxSLPts)
        { g_fn.rejRR++; Log(StringFormat("Entrada a mercado descartada: R:R %.2f",rr)); return; }
     }

   //--- riesgo de cuenta
   if(!g_risk.DailyLossOK(g_clock.NYMidnightServer())) { g_fn.rejDaily++;  return; }
   const double lots=g_risk.LotsForRisk(dir,effEntry,sl);
   if(lots<=0.0)                                       { g_fn.rejLots++;   return; }
   if(!g_risk.MarginOK(dir,lots,effEntry))             { g_fn.rejMargin++; return; }

   const string cmt=StringFormat("SB %s %s",g_clock.WindowName(w),PoolTypeToString(g_sweep.type));
   ulong ticket=0;
   if(!g_exec.Place(kind,dir,lots,entry,sl,tp,g_clock.WindowEnd(w),cmt,ticket)) { g_fn.rejSend++; return; }
   g_fn.placed++;
   if(kind==KIND_MARKET) g_fn.filled++;

   g_state=(kind==KIND_MARKET)?SB_IN_TRADE:SB_ORDER_PLACED;
   Log(StringFormat("[%s] %s %s %.2f lotes | entrada %.5f SL %.5f TP %.5f | R:R %.2f | ticket #%I64u",
                    g_clock.WindowName(w),(kind==KIND_MARKET)?"MERCADO":"LIMIT",(dir>0)?"BUY":"SELL",
                    lots,effEntry,sl,tp,rr,ticket));
  }

//+------------------------------------------------------------------+
//| ¿El FVG recién confirmado encaja con el barrido en curso?        |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Sesgo: +1 solo compras, -1 solo ventas, 0 = sin datos (no filtra) |
//+------------------------------------------------------------------+
int CurrentBias(const double refPrice)
  {
   if(InpBiasMode==BIAS_EMA)
     {
      double ma[],cl[];
      if(CopyBuffer(g_hBiasMA,0,1,1,ma)!=1 || CopyClose(_Symbol,InpBiasTF,1,1,cl)!=1) return 0;
      if(cl[0]>ma[0]) return +1;
      if(cl[0]<ma[0]) return -1;
      return 0;
     }
   if(InpBiasMode==BIAS_PD_RANGE)
     {
      const double h=g_liq.PDH(), l=g_liq.PDL();
      if(h<=0.0 || l<=0.0 || h<=l) return 0;
      return (refPrice<(h+l)*0.5)?+1:-1;      // discount -> compras; premium -> ventas
     }
   return 0;
  }

void EvaluateFVG(const int w,const SFVG &f)
  {
   const bool dirOk  =(f.dir==-g_sweep.side);
   const bool afterOk=(f.tC1>=g_sweep.breachTime);
   const bool winOk  =g_clock.InWindow(w,f.tC3);
   if(!dirOk)        g_fn.fvgDirMismatch++;
   else if(!afterOk) g_fn.fvgBeforeSweep++;
   else if(!winOk)   g_fn.fvgOutOfWindow++;
   else if(!g_mssOk) { g_fn.fvgNoMSS++; Log("FVG válido pero sin MSS confirmado"); }
   else
     {
      const int b=(InpBiasMode==BIAS_OFF)?0:CurrentBias(f.ce);
      if(b!=0 && b!=f.dir)
        {
         g_fn.fvgBias++;
         Log(StringFormat("FVG %s descartado por sesgo (%s)",(f.dir>0)?"alcista":"bajista",EnumToString(InpBiasMode)));
         return;
        }
      if(InpNoNewOrderLastMin>0 && (long)(g_clock.WindowEnd(w)-TimeCurrent())<(long)InpNoNewOrderLastMin*60)
        {
         g_fn.rejLate++;
         Log(StringFormat("FVG descartado: quedan menos de %d min de ventana",InpNoNewOrderLastMin));
         return;
        }
      g_fn.fvgCandidates++;
      TryEnter(w,f);
     }
  }

//+------------------------------------------------------------------+
//| Lógica principal: 1 vez por vela cerrada del TF de ejecución     |
//+------------------------------------------------------------------+
void OnNewExecBar(void)
  {
   const datetime now=TimeCurrent();

   double atrExec=0.0, atrSwing=0.0;
   if(!ReadATR(g_hAtrExec,atrExec) || !ReadATR(g_hAtrSwing,atrSwing)) return;   // ATR aún no calculado
   ResetLastError();
   if(CopyRates(_Symbol,InpExecTF,1,3,g_rates)!=3)
     { Log(StringFormat("CopyRates falló (err=%d)",GetLastError())); return; }

   //--- contexto diario y liquidez
   if(g_clock.RefreshDay(now))
     {
      g_liq.OnNewDay(g_clock,now,atrSwing);
      g_fvg.Reset();
      g_fn.days++;
      //--- cierre forzoso del viernes (evita gaps de fin de semana con la posición abierta)
      g_friCutoff=0; g_friDone=false;
      MqlDateTime nd; TimeToStruct(g_clock.NYDay(),nd);
      if(InpFridayCloseHourNY>=0 && nd.day_of_week==5)
         g_friCutoff=g_clock.NYToServer(g_clock.NYDay()+InpFridayCloseHourNY*3600+InpFridayCloseMinNY*60);
      Log(StringFormat("Nuevo día NY %s: %d pools de liquidez",
                       TimeToString(g_clock.NYDay(),TIME_DATE),g_liq.Total()));
     }
   g_liq.OnBar(g_clock,now);
   if(g_barSwing.IsNew(_Symbol,InpSwingTF)) g_liq.UpdateSwings(atrSwing);

   //--- detección (siempre, para mantener estados de FVG y pools)
   const double spread=g_risk.CurrentSpreadPts()*_Point;
   SFVG f;        ZeroMemory(f);
   SSweepEvent e; ZeroMemory(e);
   const bool hasFvg  =g_fvg.OnNewBar(g_rates,atrExec,spread,f);
   bool hasSweep=g_liq.CheckSweeps(g_rates[0],atrExec,e);
   const bool lowPrioSweep=(hasSweep && e.priority<InpMinSweepPrio);
   if(lowPrioSweep) hasSweep=false;               // swing menor: el pool queda consumido, sin señal
   if(hasFvg) DrawFVG(f);

   //--- ventana (por la hora de apertura de la vela cerrada: coherente en tester)
   const datetime barTime=g_rates[0].time;
   const int w=g_clock.WindowAt(barTime,InpSweepLeadMin*60);
   if(w!=g_win) OnWindowChange(w);
   if(w<0) { UpdateStatus(); return; }

   if(hasFvg) g_fn.fvgWin++;
   if(lowPrioSweep) g_fn.sweepsLowPrio++;

   switch(g_state)
     {
      case SB_IDLE:
         if(hasSweep)
           {
            StartSweep(e);
            UpdateMSS(g_rates[0]);
            if(hasFvg) EvaluateFVG(w,f);       // barrido y FVG confirmados en la misma vela
           }
         break;

      case SB_SWEPT:
        {
         //--- Un barrido nuevo solo redefine el contexto si es del MISMO lado (nuevo extremo)
         //--- o de MAYOR prioridad. Así, los swings menores que la propia pierna de
         //--- desplazamiento perfora/recupera no invierten la dirección buscada.
         if(hasSweep && (e.side==g_sweep.side || e.priority>g_sweep.priority))
           {
            g_fn.sweepsReplaced++;
            StartSweep(e);
           }
         else
           {
            if(hasSweep) g_fn.sweepsIgnored++;
            //--- el plazo para el FVG solo corre DENTRO de la ventana: un barrido en el margen
            //--- previo (p.ej. 09:35 NY) no caduca antes de que la ventana abra
            if(g_clock.InWindow(w,barTime)) g_sweepBars++;
            if(g_sweepBars>InpMaxBarsSweepToFVG)
              {
               g_fn.sweepsExpired++;
               Log("Barrido caducado sin FVG válido");
               g_state=SB_IDLE;
               break;
              }
           }
         UpdateMSS(g_rates[0]);
         if(hasFvg) EvaluateFVG(w,f);
         break;
        }

      case SB_ORDER_PLACED:
         if(g_exec.HasPosition())     { g_fn.filled++;  g_state=SB_IN_TRADE; Log("Orden limitada ejecutada"); }
         else if(!g_exec.HasPending()) { g_fn.expired++; g_state=SB_DONE;     Log("Orden pendiente expirada/cancelada"); }
         break;

      case SB_IN_TRADE:
         if(!g_exec.HasPosition()) { g_state=SB_DONE; Log("Posición cerrada. Ventana consumida."); }
         break;

      case SB_DONE:
         break;
     }
   UpdateStatus();
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   //--- validación de parámetros
   if(InpRiskPct<=0.0 || InpRiskPct>5.0)            { Print("InpRiskPct debe estar en (0, 5]"); return INIT_PARAMETERS_INCORRECT; }
   if(!InpWinLondon && !InpWinAM && !InpWinPM)       { Print("Activa al menos una ventana");     return INIT_PARAMETERS_INCORRECT; }
   if(PeriodSeconds(InpSwingTF)<PeriodSeconds(InpExecTF)) { Print("InpSwingTF debe ser >= InpExecTF"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMinRR<=0.0 || InpMaxRR<InpMinRR || InpFallbackRR<=0.0) { Print("Revisa los parámetros de R:R"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMinSLPts<=0 || InpMaxSLPts<=InpMinSLPts)    { Print("Revisa InpMinSLPts / InpMaxSLPts"); return INIT_PARAMETERS_INCORRECT; }
   if(InpBrokerGMTWinter<-12 || InpBrokerGMTWinter>14) { Print("InpBrokerGMTWinter fuera de rango"); return INIT_PARAMETERS_INCORRECT; }

   const bool optimizing=(bool)MQLInfoInteger(MQL_OPTIMIZATION);
   const bool tester    =(bool)MQLInfoInteger(MQL_TESTER);
   g_verbose=InpVerbose && !optimizing;
   g_draw   =InpDraw && !optimizing && (!tester || (bool)MQLInfoInteger(MQL_VISUAL_MODE));

   //--- reloj NY
   g_clock.Init(InpBrokerGMTWinter,InpBrokerDST);
   g_clock.SetWindow(0,InpWinLondon,180,240);
   g_clock.SetWindow(1,InpWinAM,    600,660);
   g_clock.SetWindow(2,InpWinPM,    840,900);
   g_clock.ValidateLive();
   if(InpValidateHistory && !optimizing) g_clock.ValidateHistory();

   //--- indicadores (una sola vez)
   ResetLastError();
   g_hAtrExec =iATR(_Symbol,InpExecTF,InpATRPeriod);
   g_hAtrSwing=iATR(_Symbol,InpSwingTF,InpATRPeriod);
   if(g_hAtrExec==INVALID_HANDLE || g_hAtrSwing==INVALID_HANDLE)
     { PrintFormat("No se pudo crear iATR (err=%d)",GetLastError()); return INIT_FAILED; }
   if(InpBiasMode==BIAS_EMA)
     {
      ResetLastError();
      g_hBiasMA=iMA(_Symbol,InpBiasTF,InpBiasEMA,0,MODE_EMA,PRICE_CLOSE);
      if(g_hBiasMA==INVALID_HANDLE)
        { PrintFormat("No se pudo crear iMA de sesgo (err=%d)",GetLastError()); return INIT_FAILED; }
     }

   //--- módulos
   g_fvg.Init(InpExecTF,InpMinGapPts,InpMinGapATR,InpDispATR,InpMinBodyRatio,InpFVGExpiryBars,InpMinGapSpread);
   g_liq.Init(InpSwingTF,InpSwingN,InpReclaimBars,InpMinPenPts,InpMaxPenATR,InpEqTolATR,InpUseSwingPools);
   g_risk.Init(_Symbol,InpMagic,InpRiskPct,InpRiskOnEquity,InpMaxDailyLossPct,InpCommissionPerLot,InpMaxSpreadAbsPts);
   if(!g_exec.Init(_Symbol,InpMagic,InpSlippagePts)) return INIT_FAILED;

   ArraySetAsSeries(g_rates,true);
   ArraySetAsSeries(g_buf,true);
   ZeroMemory(g_sweep);
   ZeroMemory(g_fn);
   g_state=SB_IDLE; g_win=-1;

   //--- avisos de entorno
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("Aviso: la cuenta no es hedging. El EA limita a 1 posición, funcionará igualmente.");
   if(StringFind(_Symbol,"EURUSD")<0)
      PrintFormat("Aviso: parámetros por defecto calibrados para EURUSD; revisa puntos/ATR para %s",_Symbol);

   PrintFormat("SilverBullet v1.08 iniciado: %s, ejec %s, swings %s, riesgo %.2f%%, broker GMT%+d DST=%s, sesgo %s, prio. barrido >= %d",
               _Symbol,EnumToString(InpExecTF),EnumToString(InpSwingTF),InpRiskPct,
               InpBrokerGMTWinter,EnumToString(InpBrokerDST),EnumToString(InpBiasMode),InpMinSweepPrio);
   if(StringLen(AccountInfoString(ACCOUNT_CURRENCY))!=3)
      PrintFormat("Aviso: divisa de cuenta '%s'. En el tester elige USD en lugar de 'pips' para que comisión y riesgo sean reales.",
                  AccountInfoString(ACCOUNT_CURRENCY));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Embudo: dónde se pierden las señales                             |
//+------------------------------------------------------------------+
void PrintFunnel(void)
  {
   Print("================ SILVER BULLET - EMBUDO DE SEÑALES ================");
   PrintFormat("Días NY procesados ............ %d",g_fn.days);
   PrintFormat("Ventanas activas .............. %d",g_fn.windows);
   PrintFormat("Barridos que abren contexto ... %d  (reemplazados %d, ignorados menores %d, caducados sin FVG %d)",
               g_fn.sweeps,g_fn.sweepsReplaced,g_fn.sweepsIgnored,g_fn.sweepsExpired);
   PrintFormat("Barridos bajo prioridad mínima  %d  (InpMinSweepPrio=%d)",g_fn.sweepsLowPrio,InpMinSweepPrio);
   PrintFormat("FVG detectados en ventana ..... %d",g_fn.fvgWin);
   PrintFormat("  con contexto SWEPT, descartados: dirección %d | previos al barrido %d | fuera de ventana %d | sin MSS %d",
               g_fn.fvgDirMismatch,g_fn.fvgBeforeSweep,g_fn.fvgOutOfWindow,g_fn.fvgNoMSS);
   PrintFormat("                                   contra sesgo %d | últimos %d min de ventana %d",
               g_fn.fvgBias,InpNoNewOrderLastMin,g_fn.rejLate);
   PrintFormat("FVG candidatos a entrada ...... %d",g_fn.fvgCandidates);
   PrintFormat("  spread en candidatos (pts): min %d | medio %.1f | max %d",
               g_fn.spreadMin,(g_fn.spreadN>0)?g_fn.spreadSum/g_fn.spreadN:0.0,g_fn.spreadMax);
   PrintFormat("  rechazos: exposición %d | spread %d (tope abs %d, %% del SL %d) | SL<min %d | SL>max %d | R:R %d | tipo orden %d",
               g_fn.rejExposure,g_fn.rejSpread,g_fn.rejSpreadAbs,g_fn.rejSpreadPct,
               g_fn.rejSLMin,g_fn.rejSLMax,g_fn.rejRR,g_fn.rejKind);
   PrintFormat("            pérdida diaria %d | lote<mínimo %d | margen %d | envío fallido %d",
               g_fn.rejDaily,g_fn.rejLots,g_fn.rejMargin,g_fn.rejSend);
   PrintFormat("Órdenes enviadas .............. %d  (ejecutadas %d, expiradas/canceladas %d)",
               g_fn.placed,g_fn.filled,g_fn.expired);
   PrintFormat("Cierres forzosos de viernes ... %d  (entradas bloqueadas tras el corte %d)",
               g_fn.friCloses,g_fn.rejFriday);
   Print("===================================================================");
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(!MQLInfoInteger(MQL_OPTIMIZATION)) PrintFunnel();
   if(g_hAtrExec !=INVALID_HANDLE) IndicatorRelease(g_hAtrExec);
   if(g_hAtrSwing!=INVALID_HANDLE) IndicatorRelease(g_hAtrSwing);
   if(g_hBiasMA  !=INVALID_HANDLE) IndicatorRelease(g_hBiasMA);
   ObjectsDeleteAll(0,SB_OBJ_PREFIX);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- cierre forzoso del viernes: una comparación de enteros por tick
   if(g_friCutoff>0 && !g_friDone && TimeCurrent()>=g_friCutoff)
     {
      const bool hadPending=g_exec.HasPending();
      if(hadPending) g_exec.CancelPendings();
      const int n=g_exec.CloseAll("cierre forzoso viernes");
      if(n>0 || hadPending)
        {
         g_fn.friCloses+=n;
         Log(StringFormat("Cierre forzoso del viernes (%02d:%02d NY): %d posición(es) cerrada(s)%s",
                          InpFridayCloseHourNY,InpFridayCloseMinNY,n,hadPending?", pendientes canceladas":""));
        }
      if(!g_exec.HasPosition()) g_friDone=true;     // si algo falló, reintenta en el siguiente tick
     }
   g_exec.Manage(InpBEAtR,InpBEOffsetPts,InpMaxHoldMin*60);   // barato: sale si no hay posiciones
   if(!g_barExec.IsNew(_Symbol,InpExecTF)) return;
   OnNewExecBar();
  }

//+------------------------------------------------------------------+
//| Criterio personalizado de optimización                           |
//| PF(acotado a 10) * sqrt(trades) * (1 - DD%/100)                  |
//| Devuelve 0 si hay menos de InpTesterMinTrades operaciones.       |
//+------------------------------------------------------------------+
double OnTester()
  {
   const double trades=TesterStatistics(STAT_TRADES);
   if(trades<InpTesterMinTrades) return 0.0;
   const double gp =TesterStatistics(STAT_GROSS_PROFIT);
   const double gl =MathAbs(TesterStatistics(STAT_GROSS_LOSS));
   const double dd =TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   //--- PF acotado: sin pérdidas MT5 reporta PF=0, lo que hundiría a las mejores pasadas
   double pf=(gl>0.0)?gp/gl:((gp>0.0)?10.0:0.0);
   pf=MathMin(pf,10.0);
   const double score=pf*MathSqrt(trades)*MathMax(0.0,1.0-dd/100.0);
   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      PrintFormat("OnTester: %d operaciones | PF %.2f | DD equity %.2f%% | neto %.2f | puntuación %.3f",
                  (int)trades,pf,dd,TesterStatistics(STAT_PROFIT),score);
   return score;
  }
//+------------------------------------------------------------------+
