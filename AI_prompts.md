# AI Prompts for Trading Bot Development

---

## 1. Autonomous Trading Bot for MetaTrader 5 (MT5)

### Description

Create a detailed and autonomous trading bot that operates on MetaTrader 5 (MT5) without any human intervention. The bot should integrate with an AI database or AI system for continuous market analysis, decision-making, and order execution.

### Requirements

- Perform all tasks from initial market analysis to placing trades and managing open positions independently after startup.
- Utilize AI-powered data analysis to identify trading opportunities, including but not limited to technical indicators, patterns, and market sentiment.
- Integrate seamlessly with the MetaTrader 5 API for real-time market data, order execution, and position management.
- Implement risk management strategies such as stop-loss, take-profit, and position sizing.
- Continuously monitor trades and market conditions to adjust or close trades accordingly.
- Ensure robustness with error handling and logging for transparency and troubleshooting.

### Step-by-Step Instructions

1. Connect to the AI database or service which provides market analysis.
2. Fetch or receive real-time market data from MT5.
3. Use AI insights to generate trading signals.
4. Execute trades automatically on MT5 based on these signals.
5. Manage risk by setting appropriate stop-loss and take-profit levels.
6. Monitor open positions and market changes to modify or close trades when necessary.
7. Log all actions, decisions, and errors for audit and refinement.

### Output Format

Provide a comprehensive implementation plan or source code blueprint for the trading bot suitable for MT5, including interaction with the AI database, trading strategy logic, and error management. If possible, give example code snippets or pseudocode illustrating key components.

### Notes

- Prioritize safety and compliance with trading platform rules.
- Clarify any assumptions about the AI database's format or API.
- Emphasize complete automation starting from initialization with no further human input required.

---

## 2. 9 EMA-Based Expert Advisor (EA) for MT5

### Description

Create a detailed and effective MetaTrader 5 (MT5) expert advisor (EA) AI bot that uses the 9-period Exponential Moving Average (9 EMA) as its core trading indicator. The bot should analyze market data, identify trading signals based on the 9 EMA crossover or other related strategies, and execute buy or sell orders automatically.

### Requirements

- Implement the 9 EMA indicator calculation on price data.
- Develop trading logic that triggers entries and exits based on the 9 EMA pattern or crossovers.
- Incorporate risk management features such as stop-loss, take-profit, and position sizing.
- Optimize the bot’s decision-making process for various market conditions.
- Provide clear and structured MQL5 code compatible with the MT5 platform.

### Steps

1. Explain the concept and calculation of the 9 EMA.
2. Outline the trading strategy using the 9 EMA (e.g., buy when price crosses above the 9 EMA, sell when it crosses below).
3. Develop the EA structure, including initialization, deinitialization, and the `OnTick` function.
4. Code the 9 EMA indicator logic.
5. Implement signal detection and trading order execution.
6. Add risk management parameters.
7. Include comments and documentation within the code for clarity.

### Output Format

Provide the complete MQL5 source code for the MT5 expert advisor implementing the 9 EMA trading strategy. Include comprehensive comments explaining each part of the code and a summary of how the bot operates.

---

## 3. Multi-Timeframe Forex Robot for MT5

### Strategy Overview

#### Timeframes and Indicators

- **Daily timeframe (HTF)**:
  - RSI: 25-period with levels 46 (sell) and 54 (buy).
  - ATR: 14-period.
- **1-hour timeframe (Semi HTF)**:
  - RSI: 25-period with levels 46 (sell) and 54 (buy).
  - ATR: 14-period.
- **15-minute timeframe (LTF)**:
  - RSI: 7-period with levels 26 (buy) and 74 (sell).
  - ATR: 14-period.

#### Buy Entry Logic

1. **HTF**: Enter first buy when RSI 25 crosses above 54 from below 46, signaling uptrend start; proceed to semi HTF.
2. **Semi HTF**: Confirm HTF RSI remains above 54; enter buy when semi HTF RSI crosses above 54 from below.
3. **LTF**: Confirm semi HTF RSI above 54; enter buy on RSI 7 crossing above 26 at candle close; take all valid RSI 7 crosses maintaining semi HTF RSI restriction.
4. **Exit**: Close all buy trades if HTF RSI crosses below 46 (trend reversal).

#### Sell Entry Logic

1. **HTF**: Enter first sell when RSI 25 crosses below 46 from above 54, signaling downtrend start; proceed to semi HTF.
2. **Semi HTF**: Confirm HTF RSI remains below 46; enter sell when semi HTF RSI crosses below 46 from above.
3. **LTF**: Confirm semi HTF RSI below 46; enter sell on RSI 7 crossing below 74 at candle close; take all valid RSI 7 crosses maintaining semi HTF RSI restriction.
4. **Exit**: Close all sell trades if HTF RSI crosses above 54 (trend reversal).

#### Trade Management

- **Lot Size**: Base lot size at 0.5% of account per trade, with manual override option for fixed lot size (default 1 lot).
- **Stop Loss**: 2x ATR.
- **Take Profit**: 6x ATR for HTF and semi HTF trades; 4x ATR for LTF trades.
- **Optional Breakeven**: Activate at 2.5x ATR plus 0.5x ATR buffer.
- **Daily Drawdown Limit**: 4% maximum.

### Customization and Additional Features

- All indicator parameters and trade management settings fully customizable.
- Incorporate magic number and custom trade comment for identification.
- Implement a professional-grade dashboard displaying:
  - Trend direction and signal status across all three timeframes.
  - Current account profit/loss, drawdown, and equity information.

### Technical Requirements

- Ensure high optimization to prevent memory leaks and array overflows.
- Avoid any lagging through efficient data handling and error catching.
- Implement comprehensive error handling and recovery mechanisms.

### Output Format

- Provide the complete MT5 Expert Advisor code implementing the above strategy in MQL5 language.
- Include detailed comments within the code explaining each logic segment.
- Supply instructions for customizing indicator and trade parameters.
- Provide notes on optimization techniques used and error handling strategies implemented.

---

## 4. Advanced Forex Trading Robot for MT5

### Strategy Details

#### Timeframes & Indicators

- **Daily (HTF)**:
  - RSI: Period 25; Buy Level = 54; Sell Level = 46.
  - ATR: Period 14.
- **1 Hour (Semi-HTF)**:
  - RSI: Period 25; Buy Level = 54; Sell Level = 46.
  - ATR: Period 14.
- **15 Minutes (LTF)**:
  - RSI: Period 3; Buy Level = 26; Sell Level = 74.
  - ATR: Period 14.

#### Entry Criteria

- **Buy Entries**:
  - HTF: Enter first buy when RSI 25 crosses above 54 from below 46, indicating trend start.
  - Semi-HTF: After HTF buy confirmation, enter second buy when Semi-HTF RSI crosses above 54 from below.
  - LTF: With Semi-HTF RSI above 54, enter buys on every RSI 3 crossing above 26 at candle close.
- **Sell Entries**:
  - HTF: Enter first sell when RSI 25 crosses below 46 from above 54.
  - Semi-HTF: After HTF sell confirmation, enter second sell when Semi-HTF RSI crosses below 46 from above.
  - LTF: With Semi-HTF RSI below 46, enter sells on every RSI 3 crossing below 74 at candle close.

#### Exit Criteria

- Close all buy trades if HTF RSI crosses below 46.
- Close all sell trades if HTF RSI crosses above 54.

#### Trade Management

- **Lot Size**: Default 0.5% of account balance; allow manual lot size input defaulting to 1 lot.
- **Stop Loss**: 2x ATR.
- **Take Profit**: 6x ATR for HTF and Semi-HTF trades; 4x ATR for LTF trades.
- **Breakeven**: Optional activation at 2.5x ATR + 0.5x ATR buffer.
- **Daily Drawdown Limit**: 4% of account balance.

---

## 5. High-Frequency Trading Bot for MT5

### Description

Create a highly automated, aggressive high-frequency trading bot for the MetaTrader 5 (MT5) platform using MQL5. The bot must rapidly execute trades to maximize short-term profits by using technical indicators—specifically RSI, MACD, and moving averages—to identify precise automatic entry and exit points.

### Requirements

- Define an aggressive trading strategy leveraging RSI, MACD, and moving averages optimized for high-frequency scalping.
- Integrate advanced risk management features: dynamic auto exit rules, trailing stop-loss orders, and position sizing adaptive to current volatility.
- Support customizable input parameters that control aggressiveness, risk tolerance, position sizing, and indicator thresholds.
- Exclude grid system trading or hedging; only support live, real scalping with aggressive profit targeting.
