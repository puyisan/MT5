//+------------------------------------------------------------------+
//|                                                  SB_Executor.mqh |
//|  Ejecución con CTrade: órdenes limitadas/mercado, validación de  |
//|  stops/freeze level, slippage, reintentos y gestión (BE/tiempo). |
//+------------------------------------------------------------------+
#ifndef SB_EXECUTOR_MQH
#define SB_EXECUTOR_MQH

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

enum ENUM_SB_ORDER_KIND { KIND_INVALID=-1, KIND_LIMIT=0, KIND_MARKET=1 };

class CExecutor
  {
private:
   CTrade            m_trade;
   CSymbolInfo       m_sym;
   CPositionInfo     m_pos;
   COrderInfo        m_ord;
   ulong             m_magic;
   string            m_symbol;
   //--- motivo de los últimos cierres hechos por el EA (para el registro CSV)
   ulong             m_whyTk[8];
   string            m_whyTxt[8];
   double            m_whyPx[8];      // precio de mercado pedido al cerrar (bid compra / ask venta)
   int               m_whyPos;
   void              NoteClose(const ulong tk,const string why,const bool isBuy)
     {
      m_sym.RefreshRates();
      m_whyTk[m_whyPos]=tk; m_whyTxt[m_whyPos]=why; m_whyPx[m_whyPos]=isBuy?m_sym.Bid():m_sym.Ask();
      m_whyPos=(m_whyPos+1)%8;
     }

   double            MinDist(void)
     {
      const long stops =SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
      const long freeze=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      const long lvl=(stops>freeze)?stops:freeze;
      return (double)(lvl+1)*m_sym.Point();
     }
   int               m_errCount;
   string            m_lastErr;
   void              LogFail(const string what)
     {
      m_lastErr=StringFormat("%s falló: retcode=%u (%s) err=%d",what,m_trade.ResultRetcode(),
                             m_trade.ResultRetcodeDescription(),GetLastError());
      m_errCount++;
      Print("Executor: "+m_lastErr);
     }
   bool              Mine(const string sym,const long magic) const
     { return(sym==m_symbol && magic==(long)m_magic); }

public:
                     CExecutor(void) : m_magic(0),m_symbol(""),m_whyPos(0),m_errCount(0),m_lastErr("")
     { for(int i=0;i<8;i++) { m_whyTk[i]=0; m_whyTxt[i]=""; m_whyPx[i]=0.0; } }
   bool              Init(const string symbol,const ulong magic,const int deviationPts);
   double            NormPrice(const double p);
   double            MarketPrice(const int dir);
   ENUM_SB_ORDER_KIND Decide(const int dir,const double entry,const double sl,const double tp,const bool allowMarket);
   ENUM_SB_ORDER_KIND DecideAt(const int dir,const double entry,const double sl,const double tp,const bool allowMarket,
                               const double bid,const double ask);
   bool              Place(const ENUM_SB_ORDER_KIND kind,const int dir,const double lots,const double entry,
                           const double sl,const double tp,const datetime expiry,const string comment,ulong &ticket);
   bool              HasPosition(void);
   bool              HasPending(void);
   bool              CancelPendings(void);
   int               CloseAll(const string reason);
   bool              ModifySL(const double newSl);
   string            CloseReason(const ulong posTicket) const
     { for(int i=0;i<8;i++) if(m_whyTk[i]==posTicket) return m_whyTxt[i]; return ""; }
   int               ErrorCount(void) const { return m_errCount; }
   string            LastError(void) const { return m_lastErr; }
   int               CountPositions(void)
     { int n=0; for(int i=PositionsTotal()-1;i>=0;i--) if(m_pos.SelectByIndex(i) && Mine(m_pos.Symbol(),m_pos.Magic())) n++; return n; }
   int               CountPendings(void)
     { int n=0; for(int i=OrdersTotal()-1;i>=0;i--) if(m_ord.SelectByIndex(i) && Mine(m_ord.Symbol(),m_ord.Magic())) n++; return n; }
   double            CloseRequestPrice(const ulong posTicket) const
     { for(int i=0;i<8;i++) if(m_whyTk[i]==posTicket) return m_whyPx[i]; return 0.0; }
   void              Manage(const double beAtR,const double beOffsetPts,const int maxHoldSec);
  };

//+------------------------------------------------------------------+
bool CExecutor::Init(const string symbol,const ulong magic,const int deviationPts)
  {
   m_symbol=symbol; m_magic=magic;
   if(!m_sym.Name(symbol)) { PrintFormat("Executor: símbolo %s no válido",symbol); return false; }
   m_sym.Refresh();
   m_trade.SetExpertMagicNumber(magic);
   m_trade.SetDeviationInPoints((ulong)MathMax(0,deviationPts));
   m_trade.SetMarginMode();
   m_trade.SetAsyncMode(false);
   m_trade.LogLevel(LOG_LEVEL_ERRORS);
   if(!m_trade.SetTypeFillingBySymbol(symbol))
      Print("Executor: aviso, no se pudo fijar el modo de llenado por símbolo; se usa el por defecto");
   return true;
  }

//+------------------------------------------------------------------+
double CExecutor::NormPrice(const double p)
  {
   const double ts=m_sym.TickSize();
   if(ts<=0.0) return NormalizeDouble(p,m_sym.Digits());
   return NormalizeDouble(MathRound(p/ts)*ts,m_sym.Digits());
  }

double CExecutor::MarketPrice(const int dir)
  {
   m_sym.RefreshRates();
   return (dir>0)?m_sym.Ask():m_sym.Bid();
  }

//+------------------------------------------------------------------+
//| LIMIT si el precio aún no llegó a la zona; MARKET si ya está     |
//| dentro (opcional); INVALID si no cumple distancias mínimas.      |
//+------------------------------------------------------------------+
ENUM_SB_ORDER_KIND CExecutor::Decide(const int dir,const double entry,const double sl,const double tp,const bool allowMarket)
  {
   if(!m_sym.RefreshRates()) return KIND_INVALID;
   return DecideAt(dir,entry,sl,tp,allowMarket,m_sym.Bid(),m_sym.Ask());
  }

//--- misma decisión con precios dados (reconstrucción de velas pasadas)
ENUM_SB_ORDER_KIND CExecutor::DecideAt(const int dir,const double entry,const double sl,const double tp,const bool allowMarket,
                                       const double bid,const double ask)
  {
   const double md=MinDist();
   if(dir>0)
     {
      if(entry-sl<md || tp-entry<md) return KIND_INVALID;
      if(ask>=entry+md) return KIND_LIMIT;
      if(allowMarket && ask-sl>=md && tp-ask>=md) return KIND_MARKET;
     }
   else
     {
      if(sl-entry<md || entry-tp<md) return KIND_INVALID;
      if(bid<=entry-md) return KIND_LIMIT;
      if(allowMarket && sl-bid>=md && bid-tp>=md) return KIND_MARKET;
     }
   return KIND_INVALID;
  }

//+------------------------------------------------------------------+
bool CExecutor::Place(const ENUM_SB_ORDER_KIND kind,const int dir,const double lots,const double entry,
                      const double sl,const double tp,const datetime expiry,const string comment,ulong &ticket)
  {
   ticket=0;
   if(kind==KIND_LIMIT)
     {
      ENUM_ORDER_TYPE_TIME tt=ORDER_TIME_GTC;
      datetime exp=0;
      const int em=(int)SymbolInfoInteger(m_symbol,SYMBOL_EXPIRATION_MODE);
      if((em&SYMBOL_EXPIRATION_SPECIFIED)!=0 && expiry>TimeCurrent()+120)
        { tt=ORDER_TIME_SPECIFIED; exp=expiry; }

      ResetLastError();
      const bool ok=(dir>0)?m_trade.BuyLimit(lots,entry,m_symbol,sl,tp,tt,exp,comment)
                           :m_trade.SellLimit(lots,entry,m_symbol,sl,tp,tt,exp,comment);
      const uint rc=m_trade.ResultRetcode();
      if(!ok || (rc!=TRADE_RETCODE_PLACED && rc!=TRADE_RETCODE_DONE) || m_trade.ResultOrder()==0)
        { LogFail((dir>0)?"BuyLimit":"SellLimit"); return false; }
      ticket=m_trade.ResultOrder();
      return true;
     }

   if(kind==KIND_MARKET)
     {
      for(int attempt=0;attempt<3;attempt++)
        {
         m_sym.RefreshRates();
         const double px=(dir>0)?m_sym.Ask():m_sym.Bid();
         ResetLastError();
         const bool ok=(dir>0)?m_trade.Buy(lots,m_symbol,px,sl,tp,comment)
                              :m_trade.Sell(lots,m_symbol,px,sl,tp,comment);
         const uint rc=m_trade.ResultRetcode();
         if(ok && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL) && m_trade.ResultDeal()>0)
           { ticket=m_trade.ResultDeal(); return true; }
         if(rc==TRADE_RETCODE_REQUOTE || rc==TRADE_RETCODE_PRICE_CHANGED || rc==TRADE_RETCODE_PRICE_OFF)
            continue;                              // reintento inmediato (sin Sleep: compatible tester)
         break;
        }
      LogFail((dir>0)?"Buy":"Sell");
      return false;
     }
   return false;
  }

//+------------------------------------------------------------------+
bool CExecutor::HasPosition(void)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(m_pos.SelectByIndex(i) && Mine(m_pos.Symbol(),m_pos.Magic())) return true;
   return false;
  }

bool CExecutor::HasPending(void)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(m_ord.SelectByIndex(i) && Mine(m_ord.Symbol(),m_ord.Magic())) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Cierra todas las posiciones del EA. Devuelve nº cerradas.        |
//+------------------------------------------------------------------+
int CExecutor::CloseAll(const string reason)
  {
   int closed=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!m_pos.SelectByIndex(i) || !Mine(m_pos.Symbol(),m_pos.Magic())) continue;
      const ulong tk=m_pos.Ticket();
      ResetLastError();
      NoteClose(tk,reason,m_pos.PositionType()==POSITION_TYPE_BUY);
      if(!m_trade.PositionClose(tk)) { LogFail(StringFormat("PositionClose #%I64u (%s)",tk,reason)); continue; }
      const uint rc=m_trade.ResultRetcode();
      if(rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_DONE_PARTIAL)
        { LogFail(StringFormat("PositionClose #%I64u (%s)",tk,reason)); continue; }
      PrintFormat("Executor: posición #%I64u cerrada (%s)",tk,reason);
      closed++;
     }
   return closed;
  }

//+------------------------------------------------------------------+
//| Mueve el SL de las posiciones propias (respeta stops/freeze)     |
//+------------------------------------------------------------------+
bool CExecutor::ModifySL(const double newSl)
  {
   bool ok=true;
   m_sym.RefreshRates();
   const double md=MinDist();
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!m_pos.SelectByIndex(i) || !Mine(m_pos.Symbol(),m_pos.Magic())) continue;
      const double sl=NormPrice(newSl);
      if(MathAbs(sl-m_pos.StopLoss())<m_sym.Point()/2) continue;
      const bool isBuy=(m_pos.PositionType()==POSITION_TYPE_BUY);
      if(isBuy && m_sym.Bid()-sl<md) continue;
      if(!isBuy && sl-m_sym.Ask()<md) continue;
      ResetLastError();
      if(!m_trade.PositionModify(m_pos.Ticket(),sl,m_pos.TakeProfit()))
        { LogFail(StringFormat("PositionModify #%I64u",m_pos.Ticket())); ok=false; }
     }
   return ok;
  }

bool CExecutor::CancelPendings(void)
  {
   bool all=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!m_ord.SelectByIndex(i) || !Mine(m_ord.Symbol(),m_ord.Magic())) continue;
      const ulong tk=m_ord.Ticket();
      ResetLastError();
      if(!m_trade.OrderDelete(tk) || m_trade.ResultRetcode()!=TRADE_RETCODE_DONE)
        { LogFail(StringFormat("OrderDelete #%I64u",tk)); all=false; }
     }
   return all;
  }

//+------------------------------------------------------------------+
//| Gestión ligera por tick: break-even a X R y salida por tiempo    |
//+------------------------------------------------------------------+
void CExecutor::Manage(const double beAtR,const double beOffsetPts,const int maxHoldSec)
  {
   if(PositionsTotal()==0) return;
   bool refreshed=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!m_pos.SelectByIndex(i) || !Mine(m_pos.Symbol(),m_pos.Magic())) continue;
      const ulong tk=m_pos.Ticket();

      if(maxHoldSec>0 && (long)(TimeCurrent()-m_pos.Time())>=maxHoldSec)
        {
         ResetLastError();
         NoteClose(tk,"tiempo",m_pos.PositionType()==POSITION_TYPE_BUY);
         if(!m_trade.PositionClose(tk)) LogFail(StringFormat("PositionClose #%I64u (tiempo)",tk));
         else PrintFormat("Executor: posición #%I64u cerrada por tiempo máximo",tk);
         continue;
        }
      if(beAtR<=0.0) continue;

      const double open=m_pos.PriceOpen(), sl=m_pos.StopLoss(), tp=m_pos.TakeProfit();
      if(sl<=0.0) continue;
      if(!refreshed) { m_sym.RefreshRates(); refreshed=true; }
      const double md=MinDist();

      if(m_pos.PositionType()==POSITION_TYPE_BUY)
        {
         const double risk=open-sl;
         if(risk<=0.0) continue;                               // ya en BE o mejor
         const double bid=m_sym.Bid();
         if(bid-open<beAtR*risk) continue;
         const double nsl=NormPrice(open+beOffsetPts*m_sym.Point());
         if(nsl<=sl || bid-nsl<md) continue;
         ResetLastError();
         if(!m_trade.PositionModify(tk,nsl,tp)) LogFail(StringFormat("BE #%I64u",tk));
        }
      else
        {
         const double risk=sl-open;
         if(risk<=0.0) continue;
         const double ask=m_sym.Ask();
         if(open-ask<beAtR*risk) continue;
         const double nsl=NormPrice(open-beOffsetPts*m_sym.Point());
         if(nsl>=sl || nsl-ask<md) continue;
         ResetLastError();
         if(!m_trade.PositionModify(tk,nsl,tp)) LogFail(StringFormat("BE #%I64u",tk));
        }
     }
  }

#endif // SB_EXECUTOR_MQH
//+------------------------------------------------------------------+
