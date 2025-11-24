from jesse.strategies import Strategy, cached
import jesse.indicators as ta
from jesse import utils

class Test1(Strategy):
    @property
    def ema_short(self):
        return ta.ema(self.candles, 50)

    @property
    def ema_long(self):
        return ta.ema(self.candles, 200)

    @property
    def atr(self):
        return ta.atr(self.candles, 14)

    def should_long(self) -> bool:
        return self.ema_short > self.ema_long and self.close > self.ema_short

    def should_short(self) -> bool:
        return self.ema_short < self.ema_long and self.close < self.ema_short

    def should_cancel_entry(self) -> bool:
        return True

    def go_long(self):
        entry_price = self.price
        stop_loss = entry_price - 3 * self.atr
        take_profit = entry_price + 6 * self.atr
        qty = utils.size_to_qty(self.capital * 0.1, entry_price, fee_rate=self.fee_rate) * self.leverage
        
        self.buy = qty, entry_price
        self.stop_loss = qty, stop_loss
        self.take_profit = qty, take_profit

    def go_short(self):
        entry_price = self.price
        stop_loss = entry_price + 3 * self.atr
        take_profit = entry_price - 6 * self.atr
        qty = utils.size_to_qty(self.capital * 0.1, entry_price, fee_rate=self.fee_rate) * self.leverage

        self.sell = qty, entry_price
        self.stop_loss = qty, stop_loss
        self.take_profit = qty, take_profit
