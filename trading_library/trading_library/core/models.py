# trading_library/core/models.py
from dataclasses import dataclass

@dataclass
class Order:
    order_id: str
    symbol: str
    side: str
    quantity: float
    status: str
    # ... other fields

@dataclass
class Position:
    symbol: str
    quantity: float
    average_price: float
    # ...

@dataclass
class Ticker:
    symbol: str
    bid: float
    ask: float
    last_price: float
    # ...