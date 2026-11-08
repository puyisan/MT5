//+------------------------------------------------------------------+
//|                                                   SB_Defines.mqh |
//|        Silver Bullet EA - tipos, enums y estructuras comunes     |
//+------------------------------------------------------------------+
#ifndef SB_DEFINES_MQH
#define SB_DEFINES_MQH

#define SB_MAX_WIN    3     // ventanas Silver Bullet (03, 10, 14 NY)
#define SB_MAX_POOLS  64    // tope de pools de liquidez en memoria
#define SB_MAX_FVGS   32    // tope de FVG en memoria
#define SB_OBJ_PREFIX "SB_"

//--- Regla de horario de verano que aplica el BROKER a su reloj de servidor
enum ENUM_BROKER_DST
  {
   BROKER_DST_NONE=0, // Sin DST (offset fijo)
   BROKER_DST_US  =1, // DST EE.UU. (2º dom. marzo / 1er dom. noviembre)
   BROKER_DST_EU  =2  // DST Europa (último dom. marzo / último dom. octubre)
  };

//--- Punto de entrada dentro del FVG
enum ENUM_SB_ENTRY
  {
   ENTRY_EDGE=0, // Borde cercano del FVG (mayor tasa de llenado)
   ENTRY_CE  =1  // Consequent Encroachment 50% (mejor R:R)
  };

//--- Máquina de estados por ventana
enum ENUM_SB_STATE
  {
   SB_IDLE=0,        // esperando barrido de liquidez
   SB_SWEPT,         // barrido detectado, esperando FVG en contra
   SB_ORDER_PLACED,  // orden limitada colocada
   SB_IN_TRADE,      // posición abierta
   SB_DONE           // ventana consumida (1 operación por ventana)
  };

//--- Fair Value Gap
enum ENUM_FVG_STATE { FVG_ACTIVE=0, FVG_TAPPED, FVG_INVALID, FVG_EXPIRED };

struct SFVG
  {
   int               dir;        // +1 alcista, -1 bajista
   double            top;
   double            bottom;
   double            ce;         // 50% del gap
   double            c1Extreme;  // low de C1 (alcista) / high de C1 (bajista)
   datetime          tC1;        // apertura de la vela 1
   datetime          tC3;        // apertura de la vela 3
   ENUM_FVG_STATE    state;
  };

//--- Pools de liquidez
enum ENUM_POOL_TYPE
  {
   POOL_PDH=0, POOL_PDL,
   POOL_ASIA_H, POOL_ASIA_L,
   POOL_LON_H, POOL_LON_L,
   POOL_NYAM_H, POOL_NYAM_L,
   POOL_EQH, POOL_EQL,
   POOL_SWING_H, POOL_SWING_L
  };

enum ENUM_POOL_STATE
  {
   POOL_ACTIVE=0,   // liquidez intacta
   POOL_BREACHED,   // perforada, esperando recuperación del nivel (<= K velas)
   POOL_SWEPT,      // raid válido (mecha + cierre de vuelta)
   POOL_BROKEN,     // ruptura con aceptación -> no es raid
   POOL_CONSUMED    // tomada fuera de contexto (histórico / antes de existir el EA)
  };

struct SLiqPool
  {
   ENUM_POOL_TYPE    type;
   int               side;        // +1 = BSL (máximos), -1 = SSL (mínimos)
   double            price;
   datetime          formed;      // hora servidor desde la que el pool "existe" (sin lookahead)
   int               priority;
   int               touches;
   ENUM_POOL_STATE   state;
   int               breachBars;
   datetime          breachTime;
   double            extreme;     // máximo/mínimo alcanzado al perforar
  };

struct SSweepEvent
  {
   int               side;        // lado barrido; dirección del trade = -side
   double            price;       // nivel del pool
   double            extreme;     // extremo del barrido (referencia del SL)
   datetime          breachTime;  // vela en que se perforó
   datetime          time;        // vela en que se confirmó (cierre de vuelta)
   ENUM_POOL_TYPE    type;
   int               priority;
  };

//+------------------------------------------------------------------+
string PoolTypeToString(const ENUM_POOL_TYPE t)
  {
   switch(t)
     {
      case POOL_PDH:     return "PDH";
      case POOL_PDL:     return "PDL";
      case POOL_ASIA_H:  return "AsiaH";
      case POOL_ASIA_L:  return "AsiaL";
      case POOL_LON_H:   return "LonH";
      case POOL_LON_L:   return "LonL";
      case POOL_NYAM_H:  return "NYAMH";
      case POOL_NYAM_L:  return "NYAML";
      case POOL_EQH:     return "EQH";
      case POOL_EQL:     return "EQL";
      case POOL_SWING_H: return "SwH";
      case POOL_SWING_L: return "SwL";
     }
   return "?";
  }

#endif // SB_DEFINES_MQH
//+------------------------------------------------------------------+
