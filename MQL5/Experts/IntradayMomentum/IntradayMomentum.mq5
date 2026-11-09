//+------------------------------------------------------------------+
//|                                             IntradayMomentum.mq5 |
//|  Momentum intradía "Noise Area" sobre el S&P 500 (US500Roll).    |
//|                                                                  |
//|  Basado en: Zarattini, Aziz & Barbon (2024), "Beat the Market:   |
//|  An Effective Intraday Momentum Strategy for S&P500 ETF (SPY)",  |
//|  Swiss Finance Institute RP 24-97.                               |
//|                                                                  |
//|  Reglas (fijadas antes de cualquier backtest):                   |
//|   - Apertura de referencia: 9:30 NY.                             |
//|   - Zona de ruido en cada control (10:00..15:30 NY, cada 30 min):|
//|     sigma_k = media de |cierre(k)/apertura - 1| de las últimas   |
//|     14 sesiones; banda sup = max(apertura, cierre previo) *      |
//|     (1+sigma_k); banda inf = min(apertura, cierre previo) *      |
//|     (1-sigma_k).                                                 |
//|   - Precio > max(banda sup, VWAP) -> largo; < min(banda inf,     |
//|     VWAP) -> corto.                                              |
//|   - Stop dinámico evaluado en cada control: largo = max(banda    |
//|     sup, VWAP); corto = min(banda inf, VWAP).                    |
//|   - Cierre obligatorio a las 15:55 NY: nunca pasa la noche.      |
//|  Adaptaciones al CFD: SL "de catástrofe" en el servidor (stop    |
//|  dinámico +/- ancho de la zona) y lote por % de riesgo hasta ese |
//|  SL, con tope de apalancamiento.                                 |
//+------------------------------------------------------------------+
#property copyright "puyisan"
#property version   "1.01"
#define IM_VERSION "1.01"
#property description "Intraday momentum (Noise Area) en el S&P 500 CFD, sesión regular de NY"

#include "..\SilverBullet\Include\SB_Defines.mqh"
#include "..\SilverBullet\Include\SB_NYClock.mqh"
#include "..\SilverBullet\Include\SB_Risk.mqh"
#include "..\SilverBullet\Include\SB_Executor.mqh"
#include "..\SilverBullet\Include\SB_Journal.mqh"
#include "..\SilverBullet\Include\SB_Monitor.mqh"

#define IM_MAX_CP 13

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Reloj del broker ==="
input int             InpBrokerGMTWinter   = 2;              // Offset GMT del servidor en invierno
input ENUM_BROKER_DST InpBrokerDST         = BROKER_DST_US;  // Regla DST del servidor

input group "=== Estrategia (artículo) ==="
input int             InpLookbackDays      = 14;             // Sesiones para la zona de ruido
input double          InpBandMult          = 1.0;            // Multiplicador de la zona de ruido
input bool            InpGapAdjust         = true;           // Ajustar bandas por hueco de apertura
input bool            InpUseVWAP           = true;           // Stop dinámico con VWAP
input int             InpFirstCheckMinNY   = 600;            // Primer control (min desde 00:00 NY) = 10:00
input int             InpLastCheckMinNY    = 930;            // Último control = 15:30
input int             InpCheckEveryMin     = 30;             // Frecuencia de controles (min)
input int             InpCloseMinNY        = 955;            // Cierre obligatorio = 15:55 NY
input bool            InpAllowLong         = true;           // Permitir largos
input bool            InpAllowShort        = true;           // Permitir cortos

input group "=== Riesgo ==="
input double          InpRiskPct           = 0.5;            // Riesgo por operación hasta el SL de catástrofe (% balance)
input bool            InpRiskOnEquity      = false;          // Calcular sobre equity
input double          InpMaxLeverage       = 4.0;            // Apalancamiento nocional máximo (x equity)
input double          InpHardStopMult      = 1.0;            // SL de catástrofe: stop dinámico +/- N x ancho de la zona
input double          InpMaxDailyLossPct   = 2.0;            // Pérdida diaria máx. (%), 0 = off
input double          InpCommissionPerLot  = 0.0;            // Comisión ida+vuelta por lote (divisa cuenta)
input int             InpMaxSpreadPts      = 150;            // Spread máximo (puntos; 150 = 1,5 del índice)
input int             InpSlippagePts       = 50;             // Desviación máxima en órdenes a mercado (puntos)

input group "=== Protección y avisos ==="
input double          InpMaxDDStopPct      = 8.0;            // Freno: drawdown máx. de equity desde el pico (%), 0 = off
input bool            InpKillReset         = false;          // Reiniciar freno y pico al adjuntar (volver a false después)
input bool            InpPush              = true;           // Notificaciones push
input string          InpStatusFile        = "IntradayMomentum_estado.csv"; // Archivo de estado ("" = off)
input int             InpStatusEveryMin    = 5;              // Frecuencia del archivo de estado (min)

input group "=== General ==="
input ulong           InpMagic             = 20261201;       // Magic number
input bool            InpVerbose           = true;           // Log detallado
input bool            InpJournal           = true;           // Registro CSV de operaciones
input string          InpJournalFile       = "IntradayMomentum_operaciones.csv"; // Archivo (tester: sufijo _backtest)
input int             InpTesterMinTrades   = 30;             // Mín. operaciones para puntuar en OnTester
input bool            InpAllowAnySymbol    = false;          // Permitir símbolos que no sean el S&P 500 (solo para pruebas)

//+------------------------------------------------------------------+
//| Globales                                                         |
//+------------------------------------------------------------------+
CNYClock      g_clock;
CRiskManager  g_risk;
CExecutor     g_exec;
CTradeJournal g_journal;
CNotifier     g_ntf;
CStatusFile   g_status;

bool          g_isTester=false, g_verbose=true;
datetime      g_lastM1=0;
//--- datos de la sesión del día
datetime      g_sessDay=0;          // 00:00 NY del día preparado
bool          g_sessOk=false;
double        g_open=0, g_prevClose=0;
double        g_sigma[IM_MAX_CP];
int           g_nCp=0;
//--- supervisión
double        g_peakEq=0; bool g_killed=false; string g_gvPeak="", g_gvKill="";
datetime      g_lastStatus=0; int g_errSeen=0;
string        g_lastAction="";

struct SImFunnel
  {
   int days, daysNoData, checkpoints, sigLong, sigShort, entries, exitStop, exitEOD;
   int rejSpread, rejLots, rejDaily, rejKill, rejMargin, rejSend, rejDir;
  };
SImFunnel g_fn;

void Log(const string s) { if(g_verbose) Print(s); }

//+------------------------------------------------------------------+
//| Barras M1 por hora NY                                            |
//+------------------------------------------------------------------+
//--- índice de la barra M1 que EMPIEZA en ese minuto NY de ese día (-1 si no existe)
int BarAt(const datetime nyDay,const int minNY)
  {
   const datetime srv=g_clock.NYToServer(nyDay+minNY*60);
   return iBarShift(_Symbol,PERIOD_M1,srv,true);
  }
//--- precio en el minuto NY: cierre de la barra que termina en ese minuto
bool PriceAt(const datetime nyDay,const int minNY,double &px)
  {
   const int sh=BarAt(nyDay,minNY-1);
   if(sh<0) return false;
   px=iClose(_Symbol,PERIOD_M1,sh);
   return px>0;
  }
bool OpenAt(const datetime nyDay,const int minNY,double &px)
  {
   const int sh=BarAt(nyDay,minNY);
   if(sh<0) return false;
   px=iOpen(_Symbol,PERIOD_M1,sh);
   return px>0;
  }
int CpMinute(const int k) { return InpFirstCheckMinNY+k*InpCheckEveryMin; }

//+------------------------------------------------------------------+
//| Preparación diaria: apertura, cierre previo y sigma por control  |
//| (una vez al día; ~14 x 13 búsquedas de barra)                    |
//+------------------------------------------------------------------+
bool PrepareSession(const datetime nyDay)
  {
   g_sessDay=nyDay; g_sessOk=false;
   g_nCp=MathMin(IM_MAX_CP,(InpLastCheckMinNY-InpFirstCheckMinNY)/MathMax(1,InpCheckEveryMin)+1);
   if(!OpenAt(nyDay,570,g_open)) return false;                  // 9:30 NY de hoy

   double sum[IM_MAX_CP]; ArrayInitialize(sum,0.0);
   int found=0; bool havePrev=false;
   for(int back=1;back<=45 && found<InpLookbackDays;back++)
     {
      const datetime d=nyDay-(datetime)(back*86400);
      double o=0;
      if(!OpenAt(d,570,o)) continue;                             // sin sesión (fin de semana / festivo)
      double c[IM_MAX_CP]; bool ok=true;
      for(int k=0;k<g_nCp && ok;k++) ok=PriceAt(d,CpMinute(k),c[k]);
      if(!ok) continue;
      if(!havePrev)
        {
         double pc=0;
         if(PriceAt(d,960,pc)) { g_prevClose=pc; havePrev=true; } // cierre 16:00 NY de la sesión previa
        }
      for(int k=0;k<g_nCp;k++) sum[k]+=MathAbs(c[k]/o-1.0);
      found++;
     }
   if(found<InpLookbackDays || !havePrev) return false;
   for(int k=0;k<g_nCp;k++) g_sigma[k]=sum[k]/found*InpBandMult;
   g_sessOk=true;
   return true;
  }

//--- VWAP de la sesión hasta ahora (precio típico x volumen de ticks)
double SessionVWAP(const datetime nyDay)
  {
   const datetime from=g_clock.NYToServer(nyDay+570*60);
   MqlRates r[];
   const int n=CopyRates(_Symbol,PERIOD_M1,from,TimeCurrent()-1,r);
   double pv=0,v=0;
   for(int i=0;i<n;i++) { const double tp=(r[i].high+r[i].low+r[i].close)/3.0; pv+=tp*(double)r[i].tick_volume; v+=(double)r[i].tick_volume; }
   return (v>0)?pv/v:0.0;
  }

int PositionDir(void)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong tk=PositionGetTicket(i);
      if(tk==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic) continue;
      return (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?+1:-1;
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Entrada con todos los controles de riesgo                        |
//+------------------------------------------------------------------+
void TryEnter(const int dir,const double stopDyn,const double noiseW,const int cpMin)
  {
   if((dir>0 && !InpAllowLong) || (dir<0 && !InpAllowShort)) { g_fn.rejDir++; return; }
   if(g_killed) { g_fn.rejKill++; Log("Entrada descartada: freno de emergencia activo"); return; }
   int spr=0;
   if(!g_risk.SpreadOK(spr)) { g_fn.rejSpread++; Log(StringFormat("Entrada descartada: spread %d > %d",spr,InpMaxSpreadPts)); return; }
   if(!g_risk.DailyLossOK(g_clock.NYToServer(g_sessDay))) { g_fn.rejDaily++; return; }

   const double px=g_exec.MarketPrice(dir);
   double hardSL=stopDyn-dir*InpHardStopMult*noiseW;
   if(dir>0) hardSL=MathMin(hardSL,px-noiseW*0.25);            // nunca pegado al precio
   else      hardSL=MathMax(hardSL,px+noiseW*0.25);
   hardSL=g_exec.NormPrice(hardSL);

   double lots=g_risk.LotsForRisk(dir,px,hardSL);
   //--- tope de apalancamiento nocional
   const double contract=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   const double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   const double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(contract>0 && step>0 && px>0)
     {
      const double capLots=MathFloor(eq*InpMaxLeverage/(px*contract)/step+1e-9)*step;
      if(lots>capLots) lots=capLots;
     }
   if(lots<SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)) { g_fn.rejLots++; return; }
   if(!g_risk.MarginOK(dir,lots,px)) { g_fn.rejMargin++; return; }

   const string cmt=StringFormat("IM %02d%02d %s",cpMin/60,cpMin%60,(dir>0)?"L":"S");
   ulong ticket=0;
   if(!g_exec.Place(KIND_MARKET,dir,lots,px,hardSL,0.0,0,cmt,ticket)) { g_fn.rejSend++; return; }
   g_fn.entries++;
   g_lastAction=StringFormat("%s %.1f lotes @%.2f, stop %.2f, SL %.2f",(dir>0)?"LARGO":"CORTO",lots,px,stopDyn,hardSL);
   Log("Entrada "+g_lastAction);
   g_ntf.Send("Entrada "+g_lastAction);
  }

//+------------------------------------------------------------------+
//| Un control (10:00, 10:30, ... 15:30 NY)                          |
//+------------------------------------------------------------------+
void OnCheckpoint(const int k,const int cpMin)
  {
   g_fn.checkpoints++;
   double P=0;
   if(!PriceAt(g_sessDay,cpMin,P)) return;
   const double sig=g_sigma[k];
   const double baseU=InpGapAdjust?MathMax(g_open,g_prevClose):g_open;
   const double baseL=InpGapAdjust?MathMin(g_open,g_prevClose):g_open;
   const double UB=baseU*(1.0+sig), LB=baseL*(1.0-sig);
   const double vwap=InpUseVWAP?SessionVWAP(g_sessDay):0.0;
   const double stopL=(vwap>0)?MathMax(UB,vwap):UB;
   const double stopS=(vwap>0)?MathMin(LB,vwap):LB;
   const double noiseW=g_open*sig;

   int d=PositionDir();
   //--- salida por stop dinámico (evaluado solo en el control, como en el artículo)
   if(d>0 && P<stopL) { g_exec.CloseAll("stop"); g_fn.exitStop++; Log(StringFormat("Salida largo: %.2f < stop %.2f",P,stopL)); d=0; }
   if(d<0 && P>stopS) { g_exec.CloseAll("stop"); g_fn.exitStop++; Log(StringFormat("Salida corto: %.2f > stop %.2f",P,stopS)); d=0; }

   //--- entrada (o giro tras la salida). Se exige estar también más allá del stop dinámico:
   //--- con el precio entre la banda y el VWAP se entraría ya "stopeado" en el siguiente control.
   if(d==0)
     {
      if(P>stopL)      { g_fn.sigLong++;  TryEnter(+1,stopL,noiseW,cpMin); }
      else if(P<stopS) { g_fn.sigShort++; TryEnter(-1,stopS,noiseW,cpMin); }
      if(PositionDir()!=0)
         Log(StringFormat("Control %02d:%02d NY: precio %.2f | bandas %.2f / %.2f | VWAP %.2f",cpMin/60,cpMin%60,P,LB,UB,vwap));
     }
  }

//+------------------------------------------------------------------+
//| Supervisión (igual que Silver Bullet v1.11)                      |
//+------------------------------------------------------------------+
void WriteStatus(const string forceState)
  {
   if(!g_status.Enabled()) return;
   SStatusRow r;
   const double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   r.version=IM_VERSION;
   r.estado=(forceState!="")?forceState:(g_killed?"FRENO":(PositionDir()!=0?"EN_POSICION":"ESPERA"));
   r.ventana=g_sessOk?"sesion":"-";
   r.equity=eq; r.balance=AccountInfoDouble(ACCOUNT_BALANCE); r.pico=g_peakEq;
   r.dd_pct=(g_peakEq>0)?(g_peakEq-eq)/g_peakEq:0.0; r.freno=g_killed;
   r.posiciones=g_exec.CountPositions(); r.pendientes=g_exec.CountPendings();
   r.conectado=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   r.trading=(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   r.errores=g_exec.ErrorCount(); r.ultimo_error=g_exec.LastError();
   if(g_status.Write(r)) g_lastStatus=TimeTradeServer();
  }

void KillInit(void)
  {
   const double eq=AccountInfoDouble(ACCOUNT_EQUITY), bal=AccountInfoDouble(ACCOUNT_BALANCE);
   g_killed=false;
   if(g_isTester) { g_peakEq=MathMax(eq,bal); return; }
   g_gvPeak=StringFormat("IM_%I64u_%I64d_pico",InpMagic,AccountInfoInteger(ACCOUNT_LOGIN));
   g_gvKill=StringFormat("IM_%I64u_%I64d_freno",InpMagic,AccountInfoInteger(ACCOUNT_LOGIN));
   if(InpKillReset) { GlobalVariableDel(g_gvPeak); GlobalVariableDel(g_gvKill); Print("Freno reiniciado (InpKillReset=true). Vuelve a ponerlo en false."); }
   g_peakEq=MathMax(GlobalVariableCheck(g_gvPeak)?GlobalVariableGet(g_gvPeak):MathMax(eq,bal),eq);
   GlobalVariableSet(g_gvPeak,g_peakEq);
   g_killed=GlobalVariableCheck(g_gvKill) && GlobalVariableGet(g_gvKill)>0.5;
   if(g_killed) Print("FRENO ACTIVO desde una sesión anterior: no abrirá operaciones (reanudar con InpKillReset=true).");
  }

void CheckKill(void)
  {
   if(InpMaxDDStopPct<=0.0) return;
   const double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>g_peakEq) { g_peakEq=eq; if(!g_isTester) GlobalVariableSet(g_gvPeak,eq); }
   if(g_killed || g_peakEq<=0.0) return;
   const double dd=100.0*(g_peakEq-eq)/g_peakEq;
   if(dd<InpMaxDDStopPct) return;
   g_killed=true;
   if(!g_isTester) GlobalVariableSet(g_gvKill,1.0);
   const string msg=StringFormat("FRENO DE EMERGENCIA: drawdown %.2f%% desde el pico %.2f (límite %.1f%%). No abrirá más operaciones.",dd,g_peakEq,InpMaxDDStopPct);
   Print(msg); g_ntf.Send(msg); WriteStatus("");
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRiskPct<=0.0 || InpRiskPct>5.0) { Print("InpRiskPct debe estar en (0, 5]"); return INIT_PARAMETERS_INCORRECT; }
   if(InpLookbackDays<2 || InpCheckEveryMin<1 || InpLastCheckMinNY<InpFirstCheckMinNY || InpCloseMinNY<=InpLastCheckMinNY)
     { Print("Revisa los parámetros de horario"); return INIT_PARAMETERS_INCORRECT; }
   if((InpLastCheckMinNY-InpFirstCheckMinNY)/InpCheckEveryMin+1>IM_MAX_CP)
     { PrintFormat("Demasiados controles por día (máximo %d)",IM_MAX_CP); return INIT_PARAMETERS_INCORRECT; }

   const bool optimizing=(bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_isTester=(bool)MQLInfoInteger(MQL_TESTER);
   g_verbose=InpVerbose && !optimizing;

   g_clock.Init(InpBrokerGMTWinter,InpBrokerDST);
   g_clock.ValidateLive();
   g_risk.Init(_Symbol,InpMagic,InpRiskPct,InpRiskOnEquity,InpMaxDailyLossPct,InpCommissionPerLot,InpMaxSpreadPts);
   if(!g_exec.Init(_Symbol,InpMagic,InpSlippagePts)) return INIT_FAILED;

   string jfile=InpJournalFile;
   if(g_isTester) { const int dot=StringFind(jfile,".csv"); jfile=(dot>0)?StringSubstr(jfile,0,dot)+"_backtest.csv":jfile+"_backtest"; }
   g_journal.Init(InpJournal && !optimizing,jfile,false,g_isTester,InpMagic,_Symbol,IM_VERSION);
   g_ntf.Init(InpPush,StringFormat("IM %s: ",_Symbol));
   g_status.Init(InpStatusFile!="",InpStatusFile,false);
   KillInit();
   ZeroMemory(g_fn);
   if(!optimizing) EventSetTimer(60);

   //--- la lógica depende de la sesión regular del S&P 500: rechazar otros símbolos por defecto
   string symU=_Symbol; StringToUpper(symU);
   const bool isSPX=(StringFind(symU,"US500")>=0 || StringFind(symU,"SPX")>=0 || StringFind(symU,"SP500")>=0);
   if(!isSPX && !InpAllowAnySymbol)
     {
      PrintFormat("ERROR: IntradayMomentum está diseñado para el S&P 500 (US500Roll). Símbolo actual: %s. "
                  "Elige US500Roll en el tester (o activa InpAllowAnySymbol solo para pruebas).",_Symbol);
      return INIT_PARAMETERS_INCORRECT;
     }
   PrintFormat("IntradayMomentum v%s iniciado: %s, riesgo %.2f%%, apalancamiento máx. %.1fx, lookback %d sesiones, controles %02d:%02d-%02d:%02d NY cada %d min, cierre %02d:%02d NY",
               IM_VERSION,_Symbol,InpRiskPct,InpMaxLeverage,InpLookbackDays,InpFirstCheckMinNY/60,InpFirstCheckMinNY%60,
               InpLastCheckMinNY/60,InpLastCheckMinNY%60,InpCheckEveryMin,InpCloseMinNY/60,InpCloseMinNY%60);
   WriteStatus("");
   g_ntf.Send(StringFormat("EA v%s iniciado · equity %.2f%s",IM_VERSION,AccountInfoDouble(ACCOUNT_EQUITY),g_killed?" · FRENO ACTIVO":""));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(!MQLInfoInteger(MQL_OPTIMIZATION))
     {
      Print("================ INTRADAY MOMENTUM - EMBUDO ================");
      PrintFormat("Sesiones preparadas ........... %d  (sin datos suficientes %d)",g_fn.days,g_fn.daysNoData);
      PrintFormat("Controles evaluados ........... %d",g_fn.checkpoints);
      PrintFormat("Señales ....................... largas %d | cortas %d",g_fn.sigLong,g_fn.sigShort);
      PrintFormat("Rechazos ...................... spread %d | lote<mín %d | pérdida diaria %d | freno %d | margen %d | envío %d | dirección %d",
                  g_fn.rejSpread,g_fn.rejLots,g_fn.rejDaily,g_fn.rejKill,g_fn.rejMargin,g_fn.rejSend,g_fn.rejDir);
      PrintFormat("Entradas ...................... %d  (salidas por stop dinámico %d, por cierre de sesión %d)",g_fn.entries,g_fn.exitStop,g_fn.exitEOD);
      Print("=============================================================");
     }
   if(reason!=REASON_CHARTCHANGE && reason!=REASON_PARAMETERS && reason!=REASON_RECOMPILE)
     { WriteStatus("detenido"); g_ntf.Send(StringFormat("EA detenido (motivo %d).",reason)); }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   CheckKill();
   const datetime m1=iTime(_Symbol,PERIOD_M1,0);
   if(m1==0 || m1==g_lastM1) return;                       // lógica solo en barra M1 nueva
   g_lastM1=m1;

   g_clock.RefreshDay(m1);
   const datetime nyDay=g_clock.NYDay();
   MqlDateTime t; TimeToStruct(g_clock.ServerToNY(m1),t);
   const int minNY=t.hour*60+t.min;                         // minuto NY en que empieza la barra nueva

   //--- cierre obligatorio de la sesión (y red de seguridad si algo quedó abierto)
   if(minNY>=InpCloseMinNY || minNY<570)
     {
      if(PositionDir()!=0)
        {
         const int n=g_exec.CloseAll("sesion");
         if(n>0) { g_fn.exitEOD++; Log("Cierre de sesión"); g_ntf.Send(StringFormat("Cierre de sesión: %d posición(es)",n)); }
        }
      return;
     }
   if(t.day_of_week==0 || t.day_of_week==6) return;

   //--- preparar la sesión una vez al día, al llegar la apertura
   if(g_sessDay!=nyDay && minNY>=571)
     {
      if(PrepareSession(nyDay)) { g_fn.days++; Log(StringFormat("Sesión %s: apertura %.2f, cierre previo %.2f, sigma 10:00 = %.3f%%",
                                                TimeToString(nyDay,TIME_DATE),g_open,g_prevClose,g_sigma[0]*100)); }
      else g_fn.daysNoData++;
     }
   if(!g_sessOk || g_sessDay!=nyDay) return;

   //--- ¿la barra nueva empieza justo en un control?
   if(minNY<InpFirstCheckMinNY || minNY>InpLastCheckMinNY) return;
   if((minNY-InpFirstCheckMinNY)%InpCheckEveryMin!=0) return;
   const int k=(minNY-InpFirstCheckMinNY)/InpCheckEveryMin;
   if(k<0 || k>=g_nCp) return;
   OnCheckpoint(k,minNY);
  }

void OnTimer()
  {
   if(g_isTester) return;
   if(g_exec.ErrorCount()!=g_errSeen) { g_errSeen=g_exec.ErrorCount(); g_ntf.Send("Error de ejecución: "+g_exec.LastError()); }
   if((long)(TimeTradeServer()-g_lastStatus)>=(long)MathMax(1,InpStatusEveryMin)*60) WriteStatus("");
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   const string closed=g_journal.OnDeal(trans.deal,g_exec.CloseReason(trans.position),g_exec.CloseRequestPrice(trans.position));
   if(closed!="") { g_ntf.Send(closed+StringFormat(" · balance %.2f",AccountInfoDouble(ACCOUNT_BALANCE))); WriteStatus(""); }
  }

double OnTester()
  {
   const double trades=TesterStatistics(STAT_TRADES);
   if(trades<InpTesterMinTrades) return 0.0;
   const double gp=TesterStatistics(STAT_GROSS_PROFIT), gl=MathAbs(TesterStatistics(STAT_GROSS_LOSS));
   const double dd=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double pf=(gl>0.0)?gp/gl:((gp>0.0)?10.0:0.0); pf=MathMin(pf,10.0);
   return pf*MathSqrt(trades)*MathMax(0.0,1.0-dd/100.0);
  }
//+------------------------------------------------------------------+
