//+------------------------------------------------------------------+
//|                                                       SB_FVG.mqh |
//|  Detector de Fair Value Gaps de 3 velas.                         |
//|  Solo trabaja con velas CERRADAS (sin repintado).                |
//|  Array de entrada como serie: r[0]=C3, r[1]=C2, r[2]=C1.         |
//+------------------------------------------------------------------+
#ifndef SB_FVG_MQH
#define SB_FVG_MQH

#include "SB_Defines.mqh"

class CFVGDetector
  {
private:
   SFVG              m_fvgs[];
   int               m_tfSec;
   double            m_minGapPts;
   double            m_minGapATR;
   double            m_dispATR;
   double            m_minBodyRatio;
   double            m_spreadMult;
   int               m_expiryBars;

   bool              Detect(const MqlRates &r[],const double atr,const double spread,SFVG &f);
   void              UpdateStates(const MqlRates &bar);
   void              Push(const SFVG &f);

public:
                     CFVGDetector(void) : m_tfSec(60),m_minGapPts(0),m_minGapATR(0),
                                          m_dispATR(0),m_minBodyRatio(0),m_spreadMult(0.5),m_expiryBars(30) {}
   void              Init(const ENUM_TIMEFRAMES tf,const double minGapPts,const double minGapATR,
                          const double dispATR,const double minBodyRatio,const int expiryBars,
                          const double spreadMult);
   bool              OnNewBar(const MqlRates &r[],const double atr,const double spread,SFVG &out);
   void              Reset(void) { ArrayResize(m_fvgs,0); }
   int               Total(void) const { return ArraySize(m_fvgs); }
  };

//+------------------------------------------------------------------+
void CFVGDetector::Init(const ENUM_TIMEFRAMES tf,const double minGapPts,const double minGapATR,
                        const double dispATR,const double minBodyRatio,const int expiryBars,
                        const double spreadMult)
  {
   m_spreadMult  =MathMax(0.0,spreadMult);
   m_tfSec       =PeriodSeconds(tf);
   m_minGapPts   =minGapPts;
   m_minGapATR   =minGapATR;
   m_dispATR     =dispATR;
   m_minBodyRatio=minBodyRatio;
   m_expiryBars  =expiryBars;
   Reset();
  }

//+------------------------------------------------------------------+
//| Validación: tamaño mínimo + desplazamiento real en C2            |
//+------------------------------------------------------------------+
bool CFVGDetector::Detect(const MqlRates &r[],const double atr,const double spread,SFVG &f)
  {
   const double minGap=MathMax(MathMax(m_minGapPts*_Point,m_minGapATR*atr),m_spreadMult*spread);

   const double body2 =MathAbs(r[1].close-r[1].open);
   const double range2=r[1].high-r[1].low;
   if(range2<=0.0 || atr<=0.0) return false;
   if(body2<m_dispATR*atr || body2/range2<m_minBodyRatio) return false;   // sin desplazamiento

   ZeroMemory(f);
   if(r[0].low>r[2].high && r[1].close>r[1].open && (r[0].low-r[2].high)>=minGap)
     {
      f.dir=+1; f.bottom=r[2].high; f.top=r[0].low; f.c1Extreme=r[2].low; f.c2Extreme=r[1].low;
     }
   else if(r[0].high<r[2].low && r[1].close<r[1].open && (r[2].low-r[0].high)>=minGap)
     {
      f.dir=-1; f.top=r[2].low; f.bottom=r[0].high; f.c1Extreme=r[2].high; f.c2Extreme=r[1].high;
     }
   else
      return false;

   f.ce   =NormalizeDouble((f.top+f.bottom)*0.5,_Digits);
   f.tC1  =r[2].time;
   f.tC3  =r[0].time;
   f.state=FVG_ACTIVE;
   return true;
  }

//+------------------------------------------------------------------+
//| Ciclo de vida: ACTIVE -> TAPPED / INVALID / EXPIRED              |
//+------------------------------------------------------------------+
void CFVGDetector::UpdateStates(const MqlRates &bar)
  {
   const long maxAge=(long)m_expiryBars*m_tfSec;
   const int n=ArraySize(m_fvgs);
   for(int i=0;i<n;i++)
     {
      if(m_fvgs[i].state!=FVG_ACTIVE && m_fvgs[i].state!=FVG_TAPPED) continue;
      if(m_fvgs[i].dir>0)
        {
         if(bar.close<m_fvgs[i].bottom)       m_fvgs[i].state=FVG_INVALID;
         else if(bar.low<=m_fvgs[i].top)      m_fvgs[i].state=FVG_TAPPED;
        }
      else
        {
         if(bar.close>m_fvgs[i].top)          m_fvgs[i].state=FVG_INVALID;
         else if(bar.high>=m_fvgs[i].bottom)  m_fvgs[i].state=FVG_TAPPED;
        }
      if(m_fvgs[i].state==FVG_ACTIVE && (long)(bar.time-m_fvgs[i].tC3)>maxAge)
         m_fvgs[i].state=FVG_EXPIRED;
     }
  }

//+------------------------------------------------------------------+
void CFVGDetector::Push(const SFVG &f)
  {
   int n=ArraySize(m_fvgs);
   if(n>=SB_MAX_FVGS)
     {
      for(int i=1;i<n;i++) m_fvgs[i-1]=m_fvgs[i];
      n--;
     }
   ArrayResize(m_fvgs,n+1,SB_MAX_FVGS);
   m_fvgs[n]=f;
  }

//+------------------------------------------------------------------+
//| Llamar SOLO una vez por vela cerrada del TF de ejecución         |
//+------------------------------------------------------------------+
bool CFVGDetector::OnNewBar(const MqlRates &r[],const double atr,const double spread,SFVG &out)
  {
   if(ArraySize(r)<3) return false;
   UpdateStates(r[0]);
   if(!Detect(r,atr,spread,out)) return false;
   Push(out);
   return true;
  }

#endif // SB_FVG_MQH
//+------------------------------------------------------------------+
