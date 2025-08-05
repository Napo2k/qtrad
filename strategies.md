# Strategy Index

This index will contain text descriptions for strategies that will need to be converted into code.

## Convertible Note Strategy

I recently discovered an extremely predictable strategy that has thus far not yielded me a losing trade. This strategy was developed to exploit specific forced market mechanics that effectively put extreme sell pressure on stocks during specific time windows.

This strategy is the convertible note strategy. It goes like this:

1. Company issues a press release announcing a convertible note issuance.

2. Go and check the filing. There will be an exhibit 99.1 as an attachment. Read this, and look for a pricing window (if not already priced). This pricing window is generally a VWAP during a small timespan on the next trading day. If the filing is released in the pre-market, it will be that same day. Here is the recent filing from MARA on Wednesday. It mentions 2 PM through 4 PM EST.

3. Open a PUT contract (short duration is riskier but reward is insane) shortly before the pricing window starts. I would suggest 1-2 hours prior. If you open one in the morning, the price will likely bounce around a bit before declining into the window. The only thing that matters for the pricing here is the VWAP during the window.

4. Sell the PUT shortly after the pricing window starts. Often, stocks will flatline. Here is another example of the exact same thing. Every time I have seen this happen, price action is almost the exact same, and I will explain why.

This price action isn't due to normal bullish/bearish mechanics, or even shares actually being sold into the market. It is due to institutional bond hedging. When an institution buys the bonds, or intends to buy the bonds, they hedge their positions by selling/shorting the underlying stock. This is a mechanical process that happens every single time a bond is issued.

Sometimes convertible note announcements are pre-priced, and the note selling takes place the next trading day. What is the plan then?

The plan is the same. As the bonds get sold to qualified institutional buyers, these institutions short the underlying to hedge the position, and generally, these institutions are allowed to short naked. Here is ASTS, which happened today. Due to the convertible note selling, there was excess sell pressure on the stock. Even though the stock is in a bullish pattern on the daily, the sell pressure from the hedging today overwhelmed the buy pressure.

While this strategy isn't an everyday occurrence since companies don't release these kinds of filings all the time, it is definitely something to keep in the toolkit since it can yield 100%+ returns consistently if done correctly. I personally generally paper-hand out when I get a minimum of 20% gain since that is still a big win for me.

This strategy doesn't use chart patterns, TA, or anything. It exploits forced institutional hedging mechanics, which yield predictable and repeatable chart patterns.

## Hybrid Strategy

### Longer-Term Swing Trades

In high-conviction businesses where both technical and fundamental setups align.

### Day Trades

Positions fully opened and closed within market hours.

#### Indicators

- 10-day SMA (Simple Moving Average)
- MACD (Moving Average Convergence Divergence)

#### Rules of Engagement

- Enter long or short when price breaks above or below the 10-day SMA, confirmed by a bullish or bearish MACD crossover.
- Size up in each trade, scaling out quickly after 1%, 2%, or 3% moves, while letting a portion of the position “run.”

#### Execution

- Trade the underlying stock rather than options (though options can work if used properly).
- Scale profits quickly—because if you’re not taking profits, someone else is—and let the last 25% ride until it hits a stop at either your entry or the previous day’s lows.

## 200 EMA + Pullbacks

### Step 1: Identify the Direction of the Trend

- **Method**: Use a 200-session Exponential Moving Average (EMA).
  - If the price is above the 200 EMA, it indicates an uptrend.
  - If the price is below the 200 EMA, it indicates a downtrend.

### Step 2: Look for Discounts within the Trend (Pullbacks)

- **Method**: Use a 20-session Exponential Moving Average (EMA).
- **Interpretation**: The 20 EMA helps identify "pullbacks" or temporary corrections within the main trend.
  - In an uptrend, look for price drops towards the 20 EMA.
  - In a downtrend, look for price increases towards the 20 EMA.

### Step 3: Confirm the End of the Pullback

- **Method**: Use the Stochastic Oscillator indicator.
- **Interpretation**:
  - Overbought: Stochastic is above 80.
  - Oversold: Stochastic is below 20.
  - Divergence: Price moves in one direction while the Stochastic moves in the opposite.

#### Confirmation for Trades

- In uptrends, during a pullback, look for the Stochastic to indicate oversold conditions (below 20).
- In downtrends, during a pullback, look for the Stochastic to indicate overbought conditions (above 80).

#### Executing the Strategy

- **Entry**: Enter a position when the price starts to continue in the direction of the main trend after the pullback and Stochastic confirmation.
- **Stop Loss**:
  - For sell positions (downtrend): Place the stop loss above the previous high.
  - For buy positions (uptrend): Place the stop loss below the previous low.
- **Take Profit**: Aim for a minimum risk-reward ratio of 3:1. Since the strategy relies on trends, there's a high probability of continued movement.

## Three Candle

### Three-Candle Pattern

- The maximum of two candles prior must be greater than the maximum of one candle prior.
- The minimum of two candles prior must be less than the minimum of one candle prior.
- The closing price of the current candle must be higher than the maximum of one candle prior.

### Indicators

- 40-session Exponential Moving Average (EMA).
- 21-session Average True Range (ATR).

### Trade Execution

- **Entry**: If the three-candle pattern conditions are met and the price is above the 40 EMA, a market buy order is executed at the opening of the next candle.
- **Stop Loss**: Placed at two times the 21-session ATR.
- **Take Profit**: Set at a risk-to-reward ratio of 2:1.

## D1 Deceleration + H1 Fibonacci

### D1 Deceleration

- Each D1 candle’s range (high-low) shrinking?

### Swing Range for Fibonacci (H1)

- Calculate swing high/low from the last 8 bars

### M5 MA Break

- Should we use a specific EMA here (e.g., 20 EMA)?
  - EMA 50
- Is it a bullish/bearish close above/below the EMA?
  - This is to buy so it should be a bullish close

### ATR Settings

- Fixed % targets like “1.5x ATR SL, 2x ATR TP”

### Risk Per Trade

- 5%

## Multi Timeframe

### 1. Entry Conditions

- What triggers a Buy or Sell?
  - Deceleration is observed on the daily chart
  - The convergence of the price hitting both the 0.618 Fibonacci level and the 50 EMA on the hourly chart is a strong indication of an optimal entry point for a buy order.
  - The final execution occurs when the 5-minute chart breaks a moving average.
- Which indicators or price conditions are used?
  - 50 EMA and Fibonacci levels
- Any specific timeframe?
  - D1, H1 and M5

### 2. Exit Conditions

- When do you close a trade?
- Do you use:
  - Fixed Stop Loss / Take Profit?
    - based on volatility (e.g., ATR)

### 3. Risk Management

- Fixed lot size or dynamic based on balance?
  - Based on balance
- SL and TP in pips or ATR?
  - These would need to be defined based on volatility (e.g., ATR) or fixed percentages.	

### 4. Filters (Optional)

- Trade only during specific hours?
  - Daytrading
- Avoid trading on Fridays or during news?
  - No
- Filter by volatility or trend strength?
  - No

### 5. Other Preferences

- Symbol(s)?
  - Start with NVDA maybe
- Timeframe?
  - We need data from D1 and H1
- Any special rules or custom indicators?
  - EMA 50 and Fibonacci

## BTC strategies

### Strategy 1: Sudden Bullish Breakouts (Moving Averages Crossover)

- **Objective**: To enter during sudden upward movements.
- **Entry Condition**: Buy when a short EMA (70) crosses above a long EMA (160)
- **Exit Condition**: Close the position when the short EMA crosses below the long EMA.
- **Parameters**:
  - Timeframe: 30 minutes.
  - Long EMA: 160 periods.
  - Short EMA: 70 periods.
&nbsp;		
### Strategy 2: Quick Pullbacks (Retracements)

- **Objective**: To capitalize on small, fast pullbacks before continuation.
&nbsp;	
- **Entry Condition**: Go long when the price retreats for two consecutive bearish candles, provided it remains above an exponential moving average.
- **Exit Condition**: Close the position after a predetermined number of candles have passed since the entry.
- **Parameters**:
  - Position Size: 10% of the account.
  - Timeframe: 30 minutes.
  - Number of candles to close position: 140.
  - Exponential Moving Average: 20 periods.
&nbsp;		
### Strategy 3: Extended Corrective Phases (RSI Oversold Conditions)

- **Objective**: To build long positions during significant price declines when Bitcoin is oversold.
- **Entry Condition**: Begin buying when the Relative Strength Index (RSI) falls below 35, continuing to open positions (up to a maximum of five) as long as the RSI remains in the oversold zone.
- **Exit Condition**: Close all positions when the RSI reaches 85 (overbought).
- **Parameters**:
  - RSI Period: 21.
  - Buy Zone (Oversold): 30.
  - Sell Zone (Overbought): 85.
  - Timeframe: 5 minutes.
  - Maximum Open Positions: 5.

