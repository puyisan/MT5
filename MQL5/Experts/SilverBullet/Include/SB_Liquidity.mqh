//+------------------------------------------------------------------+
//|                                                 SB_Liquidity.mqh |
//|  Mapa de liquidez (BSL/SSL) y detección de barridos (raids).     |
//|                                                                  |
//|  Pools: PDH/PDL (día 17:00-17:00 NY), Asia (20-00 NY),           |
//|         Londres (02-05 NY), NY AM (08:30-12 NY),                 |
//|         swings fractales y equal highs/lows en el TF de swings.  |
//|  Cada pool tiene 'formed' = momento a partir del cual existe:    |
//|  nunca se usa información futura (backtest == real).             |
//+------------------------------------------------------------------+
#ifndef SB_LIQUIDITY_MQH
#define SB_LIQUIDITY_MQH

#include "SB_Defines.mqh"
#include "SB_NYClock.mqh"

class CLiquidityMap
  {
private:
   SLiqPool          m_pools[];
   ENUM_TIMEFRAMES   m_swingTF;
   int               m_swingN;
   int               m_reclaimBars;
   int               m_swingPrio;
   double            m_minPenPts;
   double            m_maxPenATR;
   double            m_eqTolATR;
   double            m_pdh;
   double            m_pdl;
   bool              m_useSwings;
   bool              m_builtLon;
   bool              m_builtNYAM;
   datetime          m_lastPivotH;
   datetime          m_lastPivotL;
   MqlRates          m_sw[];

   bool              IsSwingType(const ENUM_POOL_TYPE t) const
     { return(t==POOL_SWING_H || t==POOL_SWING_L || t==POOL_EQH || t==POOL_EQL); }
   bool              IsDone(const ENUM_POOL_STATE s) const
     { return(s==POOL_SWEPT || s==POOL_BROKEN || s==POOL_CONSUMED); }
   int               AddPool(const ENUM_POOL_TYPE t,const int side,const double px,
                             const datetime formed,const int prio);
   bool              RangeHL(const datetime fromSrv,const datetime toSrv,
                             double &hi,double &lo,const int minBars);
   void              MarkIfTaken(const int idx,const datetime from,const datetime to);
   void              BuildSession(CNYClock &clk,const datetime now,const int startMin,const int endMin,
                                  const ENUM_POOL_TYPE hiT,const ENUM_POOL_TYPE loT,const int prio);
   bool              IsPivot(const MqlRates &r[],const int c,const int n,const bool high) const;
   void              MergeOrAdd(const int side,const double px,const datetime pivotT,
                                const datetime formed,const double tol);
   void              Replay(const datetime now,const double atr);
   void              Compact(void);

public:
                     CLiquidityMap(void);
   void              Init(const ENUM_TIMEFRAMES swingTF,const int swingN,const int reclaimBars,
                          const double minPenPts,const double maxPenATR,const double eqTolATR,
                          const bool useSwings);
   void              OnNewDay(CNYClock &clk,const datetime now,const double atrSwing);
   void              OnBar(CNYClock &clk,const datetime now);
   void              UpdateSwings(const double atrSwing);
   bool              CheckSweeps(const MqlRates &bar,const double atrExec,SSweepEvent &ev);
   bool              NearestTarget(const int tradeDir,const double entry,const int minPrio,double &target) const;
   int               Total(void) const { return ArraySize(m_pools); }
   double            PDH(void) const { return m_pdh; }   // 0 si no disponible
   double            PDL(void) const { return m_pdl; }
   bool              GetPool(const int i,SLiqPool &p) const
     { if(i<0 || i>=ArraySize(m_pools)) return false; p=m_pools[i]; return true; }
  };

//+------------------------------------------------------------------+
CLiquidityMap::CLiquidityMap(void) : m_swingTF(PERIOD_M5),m_swingN(3),m_reclaimBars(3),m_swingPrio(1),
                                     m_minPenPts(2),m_maxPenATR(3),m_eqTolATR(0.1),m_useSwings(true),
                                     m_pdh(0),m_pdl(0),
                                     m_builtLon(false),m_builtNYAM(false),m_lastPivotH(0),m_lastPivotL(0)
  {
   ArraySetAsSeries(m_sw,true);
  }

//+------------------------------------------------------------------+
void CLiquidityMap::Init(const ENUM_TIMEFRAMES swingTF,const int swingN,const int reclaimBars,
                         const double minPenPts,const double maxPenATR,const double eqTolATR,
                         const bool useSwings)
  {
   m_swingTF    =swingTF;
   m_swingN     =MathMax(1,swingN);
   m_reclaimBars=MathMax(1,reclaimBars);
   m_minPenPts  =minPenPts;
   m_maxPenATR  =maxPenATR;
   m_eqTolATR   =eqTolATR;
   m_useSwings  =useSwings;
   m_swingPrio  =(PeriodSeconds(swingTF)>=PeriodSeconds(PERIOD_M15))?2:1;
   ArrayResize(m_pools,0);
  }

//+------------------------------------------------------------------+
int CLiquidityMap::AddPool(const ENUM_POOL_TYPE t,const int side,const double px,
                           const datetime formed,const int prio)
  {
   if(ArraySize(m_pools)>=SB_MAX_POOLS) Compact();
   int n=ArraySize(m_pools);
   ArrayResize(m_pools,n+1,SB_MAX_POOLS);
   m_pools[n].type      =t;
   m_pools[n].side      =side;
   m_pools[n].price     =px;
   m_pools[n].formed    =formed;
   m_pools[n].priority  =prio;
   m_pools[n].touches   =1;
   m_pools[n].state     =POOL_ACTIVE;
   m_pools[n].breachBars=0;
   m_pools[n].breachTime=0;
   m_pools[n].extreme   =px;
   return n;
  }

//+------------------------------------------------------------------+
//| Máximo/mínimo de un rango temporal en M5 (1 llamada por sesión)  |
//+------------------------------------------------------------------+
bool CLiquidityMap::RangeHL(const datetime fromSrv,const datetime toSrv,
                            double &hi,double &lo,const int minBars)
  {
   if(toSrv<=fromSrv) return false;
   double h[],l[];
   ResetLastError();
   int ch=CopyHigh(_Symbol,PERIOD_M5,fromSrv,toSrv-1,h);
   int cl=CopyLow (_Symbol,PERIOD_M5,fromSrv,toSrv-1,l);
   if(ch<minBars || cl<minBars) return false;
   hi=h[ArrayMaximum(h)];
   lo=l[ArrayMinimum(l)];
   return true;
  }

//+------------------------------------------------------------------+
//| Si el precio ya superó el nivel entre su formación y 'to',       |
//| el pool ya no es liquidez disponible.                            |
//+------------------------------------------------------------------+
void CLiquidityMap::MarkIfTaken(const int idx,const datetime from,const datetime to)
  {
   if(idx<0 || to<=from) return;
   double a[];
   if(m_pools[idx].side>0)
     {
      if(CopyHigh(_Symbol,PERIOD_M1,from,to,a)>0 && a[ArrayMaximum(a)]>m_pools[idx].price)
         m_pools[idx].state=POOL_CONSUMED;
     }
   else
     {
      if(CopyLow(_Symbol,PERIOD_M1,from,to,a)>0 && a[ArrayMinimum(a)]<m_pools[idx].price)
         m_pools[idx].state=POOL_CONSUMED;
     }
  }

//+------------------------------------------------------------------+
void CLiquidityMap::BuildSession(CNYClock &clk,const datetime now,const int startMin,const int endMin,
                                 const ENUM_POOL_TYPE hiT,const ENUM_POOL_TYPE loT,const int prio)
  {
   const datetime d      =clk.NYDay();
   const datetime fromSrv=clk.NYToServer(d+startMin*60);
   const datetime toSrv  =clk.NYToServer(d+endMin*60);
   double hi=0,lo=0;
   if(!RangeHL(fromSrv,toSrv,hi,lo,6)) return;
   int a=AddPool(hiT,+1,hi,toSrv,prio); MarkIfTaken(a,toSrv,now);
   int b=AddPool(loT,-1,lo,toSrv,prio); MarkIfTaken(b,toSrv,now);
  }

//+------------------------------------------------------------------+
//| Pivote fractal estricto con n velas a cada lado                  |
//+------------------------------------------------------------------+
bool CLiquidityMap::IsPivot(const MqlRates &r[],const int c,const int n,const bool high) const
  {
   const int sz=ArraySize(r);
   if(c-n<0 || c+n>=sz) return false;
   for(int k=1;k<=n;k++)
     {
      if(high)
        { if(r[c-k].high>=r[c].high || r[c+k].high>=r[c].high) return false; }
      else
        { if(r[c-k].low<=r[c].low || r[c+k].low<=r[c].low) return false; }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Swings próximos (< tol) se fusionan en Equal Highs/Lows          |
//+------------------------------------------------------------------+
void CLiquidityMap::MergeOrAdd(const int side,const double px,const datetime pivotT,
                               const datetime formed,const double tol)
  {
   if(side>0) { if(pivotT<=m_lastPivotH) return; m_lastPivotH=pivotT; }
   else       { if(pivotT<=m_lastPivotL) return; m_lastPivotL=pivotT; }

   const int n=ArraySize(m_pools);
   for(int i=0;i<n;i++)
     {
      if(m_pools[i].state!=POOL_ACTIVE || m_pools[i].side!=side || !IsSwingType(m_pools[i].type)) continue;
      if(MathAbs(m_pools[i].price-px)>tol) continue;
      m_pools[i].type    =(side>0)?POOL_EQH:POOL_EQL;
      m_pools[i].price   =(side>0)?MathMax(m_pools[i].price,px):MathMin(m_pools[i].price,px);
      m_pools[i].touches++;
      m_pools[i].priority=MathMax(m_pools[i].priority,3);
      return;
     }
   AddPool((side>0)?POOL_SWING_H:POOL_SWING_L,side,px,formed,m_swingPrio);
  }

//+------------------------------------------------------------------+
//| Reproduce ~36h del TF de swings en orden cronológico:            |
//| añade swings al confirmarse y consume los pools ya tomados.      |
//| Solo se ejecuta 1 vez por día NY.                                |
//+------------------------------------------------------------------+
void CLiquidityMap::Replay(const datetime now,const double atr)
  {
   const int per=PeriodSeconds(m_swingTF);
   const int lookback=(int)MathMin(600,36*3600/per);
   MqlRates r[];
   ArraySetAsSeries(r,false);
   int n=CopyRates(_Symbol,m_swingTF,1,lookback,r);       // ascendente
   if(n<=2*m_swingN) return;
   const double tol=m_eqTolATR*atr;

   for(int j=0;j<n;j++)
     {
      const int np=ArraySize(m_pools);
      for(int i=0;i<np;i++)
        {
         if(m_pools[i].state!=POOL_ACTIVE || m_pools[i].formed>r[j].time) continue;
         if(m_pools[i].side>0 && r[j].high>m_pools[i].price) m_pools[i].state=POOL_CONSUMED;
         else if(m_pools[i].side<0 && r[j].low<m_pools[i].price) m_pools[i].state=POOL_CONSUMED;
        }
      if(m_useSwings && j>=2*m_swingN)
        {
         const int c=j-m_swingN;
         const datetime formed=r[j].time+per;              // confirmado al cierre de la vela j
         if(IsPivot(r,c,m_swingN,true))  MergeOrAdd(+1,r[c].high,r[c].time,formed,tol);
         if(IsPivot(r,c,m_swingN,false)) MergeOrAdd(-1,r[c].low ,r[c].time,formed,tol);
        }
     }
   Compact();
  }

//+------------------------------------------------------------------+
void CLiquidityMap::Compact(void)
  {
   const int n=ArraySize(m_pools);
   int k=0;
   for(int i=0;i<n;i++)
     {
      if(IsDone(m_pools[i].state)) continue;
      if(k!=i) m_pools[k]=m_pools[i];
      k++;
     }
   ArrayResize(m_pools,k,SB_MAX_POOLS);
  }

//+------------------------------------------------------------------+
//| Reconstrucción diaria (00:00 NY o arranque del EA)               |
//+------------------------------------------------------------------+
void CLiquidityMap::OnNewDay(CNYClock &clk,const datetime now,const double atrSwing)
  {
   ArrayResize(m_pools,0);
   m_pdh=0; m_pdl=0;
   m_builtLon=false; m_builtNYAM=false;
   m_lastPivotH=0;   m_lastPivotL=0;

   const datetime d=clk.NYDay();
   //--- PDH/PDL: último día de trading completo (17:00 -> 17:00 NY). Retrocede en fines de semana/festivos.
   datetime endNY=d-7*3600;
   for(int k=0;k<5;k++)
     {
      const datetime fromSrv=clk.NYToServer(endNY-86400);
      const datetime toSrv  =clk.NYToServer(endNY);
      double hi=0,lo=0;
      if(RangeHL(fromSrv,toSrv,hi,lo,100))
        {
         AddPool(POOL_PDH,+1,hi,toSrv,5);
         AddPool(POOL_PDL,-1,lo,toSrv,5);
         m_pdh=hi; m_pdl=lo;
         break;
        }
      endNY-=86400;
     }
   //--- Asia: 20:00 (día previo) -> 00:00 NY
   BuildSession(clk,now,-240,0,POOL_ASIA_H,POOL_ASIA_L,3);
   //--- swings + consumo de pools ya tomados
   Replay(now,atrSwing);
  }

//+------------------------------------------------------------------+
//| Sesiones que terminan durante el día: se construyen al cerrar    |
//+------------------------------------------------------------------+
void CLiquidityMap::OnBar(CNYClock &clk,const datetime now)
  {
   const datetime d=clk.NYDay();
   if(!m_builtLon && now>=clk.NYToServer(d+300*60))       // Londres 02:00-05:00 NY
     {
      BuildSession(clk,now,120,300,POOL_LON_H,POOL_LON_L,4);
      m_builtLon=true;
     }
   if(!m_builtNYAM && now>=clk.NYToServer(d+720*60))      // NY AM 08:30-12:00 NY
     {
      BuildSession(clk,now,510,720,POOL_NYAM_H,POOL_NYAM_L,3);
      m_builtNYAM=true;
     }
  }

//+------------------------------------------------------------------+
//| Incremental: en cada vela nueva del TF de swings                 |
//+------------------------------------------------------------------+
void CLiquidityMap::UpdateSwings(const double atrSwing)
  {
   if(!m_useSwings) return;
   const int cnt=2*m_swingN+1;
   if(CopyRates(_Symbol,m_swingTF,1,cnt,m_sw)!=cnt) return;   // serie: [0] = última cerrada
   const int c=m_swingN;
   const datetime formed=m_sw[0].time+PeriodSeconds(m_swingTF);
   const double tol=m_eqTolATR*atrSwing;
   if(IsPivot(m_sw,c,m_swingN,true))  MergeOrAdd(+1,m_sw[c].high,m_sw[c].time,formed,tol);
   if(IsPivot(m_sw,c,m_swingN,false)) MergeOrAdd(-1,m_sw[c].low ,m_sw[c].time,formed,tol);
   if(ArraySize(m_pools)>SB_MAX_POOLS/2) Compact();
  }

//+------------------------------------------------------------------+
//| Raid = perfora el nivel (minPen < pen <= maxPen) y cierra de     |
//| vuelta en la misma vela o en <= K velas. Si no recupera o        |
//| penetra demasiado -> ruptura (BROKEN), sin señal.                |
//| Se ejecuta en TODAS las velas (también fuera de ventana) para    |
//| que la liquidez tomada fuera de contexto quede consumida.        |
//+------------------------------------------------------------------+
bool CLiquidityMap::CheckSweeps(const MqlRates &bar,const double atrExec,SSweepEvent &ev)
  {
   const double minPen=m_minPenPts*_Point;
   const double maxPen=m_maxPenATR*atrExec;
   int best=-1;
   const int n=ArraySize(m_pools);

   for(int i=0;i<n;i++)
     {
      const ENUM_POOL_STATE st=m_pools[i].state;
      if(IsDone(st) || bar.time<m_pools[i].formed) continue;

      const int    s   =m_pools[i].side;
      const double px  =m_pools[i].price;
      const double pen =(s>0)?(bar.high-px):(px-bar.low);
      const bool   back=(s>0)?(bar.close<px):(bar.close>px);

      if(st==POOL_ACTIVE)
        {
         if(pen<=minPen) continue;
         m_pools[i].extreme   =(s>0)?bar.high:bar.low;
         m_pools[i].breachTime=bar.time;
         if(pen>maxPen)  m_pools[i].state=POOL_BROKEN;
         else if(back)   m_pools[i].state=POOL_SWEPT;
         else          { m_pools[i].state=POOL_BREACHED; m_pools[i].breachBars=1; }
        }
      else // POOL_BREACHED
        {
         m_pools[i].extreme=(s>0)?MathMax(m_pools[i].extreme,bar.high):MathMin(m_pools[i].extreme,bar.low);
         const double totalPen=(s>0)?(m_pools[i].extreme-px):(px-m_pools[i].extreme);
         if(totalPen>maxPen)                         m_pools[i].state=POOL_BROKEN;
         else if(back)                               m_pools[i].state=POOL_SWEPT;
         else if(++m_pools[i].breachBars>m_reclaimBars) m_pools[i].state=POOL_BROKEN;
        }

      if(m_pools[i].state==POOL_SWEPT && (best<0 || m_pools[i].priority>m_pools[best].priority))
         best=i;
     }
   if(best<0) return false;

   ev.side      =m_pools[best].side;
   ev.price     =m_pools[best].price;
   ev.extreme   =m_pools[best].extreme;
   ev.breachTime=m_pools[best].breachTime;
   ev.time      =bar.time;
   ev.type      =m_pools[best].type;
   ev.priority  =m_pools[best].priority;
   return true;
  }

//+------------------------------------------------------------------+
//| Draw on liquidity: pool opuesto intacto más cercano              |
//| tradeDir>0 (compra) -> BSL por encima; tradeDir<0 -> SSL debajo  |
//+------------------------------------------------------------------+
bool CLiquidityMap::NearestTarget(const int tradeDir,const double entry,const int minPrio,double &target) const
  {
   bool found=false;
   const int n=ArraySize(m_pools);
   for(int i=0;i<n;i++)
     {
      if(m_pools[i].state!=POOL_ACTIVE || m_pools[i].side!=tradeDir || m_pools[i].priority<minPrio) continue;
      const double px=m_pools[i].price;
      if(tradeDir>0 && px>entry && (!found || px<target)) { target=px; found=true; }
      if(tradeDir<0 && px<entry && (!found || px>target)) { target=px; found=true; }
     }
   return found;
  }

#endif // SB_LIQUIDITY_MQH
//+------------------------------------------------------------------+
