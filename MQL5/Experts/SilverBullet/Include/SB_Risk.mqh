//+------------------------------------------------------------------+
//|                                                      SB_Risk.mqh |
//|  Lotaje por % de riesgo, filtro de spread, límite de pérdida     |
//|  diaria y verificación de margen.                                |
//+------------------------------------------------------------------+
#ifndef SB_RISK_MQH
#define SB_RISK_MQH

class CRiskManager
  {
private:
   string            m_symbol;
   ulong             m_magic;
   double            m_riskPct;
   bool              m_useEquity;
   double            m_maxDailyLossPct;
   double            m_commPerLot;      // comisión ida+vuelta por lote (divisa de la cuenta)
   int               m_maxSpreadPts;

public:
                     CRiskManager(void) : m_symbol(""),m_magic(0),m_riskPct(0.5),m_useEquity(false),
                                          m_maxDailyLossPct(0),m_commPerLot(0),m_maxSpreadPts(0) {}
   void              Init(const string symbol,const ulong magic,const double riskPct,const bool useEquity,
                          const double maxDailyLossPct,const double commPerLot,const int maxSpreadPts)
     {
      m_symbol=symbol; m_magic=magic; m_riskPct=riskPct; m_useEquity=useEquity;
      m_maxDailyLossPct=maxDailyLossPct; m_commPerLot=commPerLot; m_maxSpreadPts=maxSpreadPts;
     }

   double            RiskMoney(void) const
     {
      const double base=m_useEquity?AccountInfoDouble(ACCOUNT_EQUITY):AccountInfoDouble(ACCOUNT_BALANCE);
      return base*m_riskPct/100.0;
     }

   //--- spread actual en puntos
   int               CurrentSpreadPts(void) const
     {
      const double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      const double pt =SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(pt<=0.0 || ask<=0.0 || bid<=0.0) return INT_MAX;
      return (int)MathRound((ask-bid)/pt);
     }

   bool              SpreadOK(int &spreadPts) const
     {
      spreadPts=CurrentSpreadPts();
      return(m_maxSpreadPts<=0 || spreadPts<=m_maxSpreadPts);
     }

   double            LotsForRisk(const int dir,const double entry,const double sl) const;
   bool              DailyLossOK(const datetime dayStartSrv) const;
   bool              MarginOK(const int dir,const double lots,const double price) const;
  };

//+------------------------------------------------------------------+
//| Lote = riesgo monetario / pérdida por lote (OrderCalcProfit).    |
//| Siempre redondeo HACIA ABAJO al step. Si queda < mínimo -> 0     |
//| (no se fuerza el lote mínimo para no exceder el riesgo).         |
//+------------------------------------------------------------------+
double CRiskManager::LotsForRisk(const int dir,const double entry,const double sl) const
  {
   if(entry<=0.0 || sl<=0.0 || entry==sl) return 0.0;
   const ENUM_ORDER_TYPE t=(dir>0)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;

   double pl=0.0, lossPerLot=0.0;
   ResetLastError();
   if(OrderCalcProfit(t,m_symbol,1.0,entry,sl,pl) && pl<0.0)
      lossPerLot=-pl;
   else
     {
      //--- fallback por tick value
      const double tv=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
      const double ts=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tv<=0.0 || ts<=0.0)
        {
         PrintFormat("RiskManager: no se puede valorar el riesgo (err=%d)",GetLastError());
         return 0.0;
        }
      lossPerLot=MathAbs(entry-sl)/ts*tv;
     }
   lossPerLot+=m_commPerLot;
   if(lossPerLot<=0.0) return 0.0;

   const double step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
   const double vmin=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
   const double vmax=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
   if(step<=0.0) return 0.0;

   const double raw=RiskMoney()/lossPerLot;
   double lots=MathFloor(raw/step+1e-9)*step;
   if(lots<vmin)
     {
      PrintFormat("RiskManager: lote calculado %.4f < mínimo %.2f -> operación descartada (riesgo excedería %.2f%%)",
                  raw,vmin,m_riskPct);
      return 0.0;
     }
   lots=MathMin(lots,vmax);
   int vd=(int)MathRound(-MathLog10(step));
   if(vd<0) vd=0;
   return NormalizeDouble(lots,vd);
  }

//+------------------------------------------------------------------+
//| P/L del día NY (cerrado + flotante) del EA                       |
//+------------------------------------------------------------------+
bool CRiskManager::DailyLossOK(const datetime dayStartSrv) const
  {
   if(m_maxDailyLossPct<=0.0) return true;
   ResetLastError();
   if(!HistorySelect(dayStartSrv,TimeCurrent()+60))
     {
      PrintFormat("RiskManager: HistorySelect falló (err=%d) -> bloqueo preventivo",GetLastError());
      return false;
     }
   double closed=0.0;
   const int nd=HistoryDealsTotal();
   for(int i=0;i<nd;i++)
     {
      const ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=(long)m_magic) continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=m_symbol) continue;
      closed+=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_COMMISSION)+
              HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_FEE);
     }
   double floating=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong pt=PositionGetTicket(i);
      if(pt==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)m_magic) continue;
      if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
      floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
     }
   const double startBal=AccountInfoDouble(ACCOUNT_BALANCE)-closed;
   const double pnl=closed+floating;
   if(startBal>0.0 && pnl<=-startBal*m_maxDailyLossPct/100.0)
     {
      PrintFormat("RiskManager: límite de pérdida diaria alcanzado (%.2f / -%.2f%%). Sin nuevas entradas hoy.",
                  pnl,m_maxDailyLossPct);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
bool CRiskManager::MarginOK(const int dir,const double lots,const double price) const
  {
   double margin=0.0;
   ResetLastError();
   if(!OrderCalcMargin((dir>0)?ORDER_TYPE_BUY:ORDER_TYPE_SELL,m_symbol,lots,price,margin))
     {
      PrintFormat("RiskManager: OrderCalcMargin falló (err=%d)",GetLastError());
      return false;
     }
   const double freeM=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin>freeM*0.95)
     {
      PrintFormat("RiskManager: margen insuficiente (req=%.2f libre=%.2f)",margin,freeM);
      return false;
     }
   return true;
  }

#endif // SB_RISK_MQH
//+------------------------------------------------------------------+
