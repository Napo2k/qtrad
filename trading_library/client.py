# trading_library/core/client.py
import requests
import json
from .. import config  # Import config from the same package

class BrokerAPIClient:
    def __init__(self):
        self.api_key = config.API_KEY
        self.api_secret = config.API_SECRET
        self.base_url = config.BROKER_API_URL

    def _make_request(self, endpoint, method="GET", params=None, data=None):
        headers = {
            "X-API-KEY": self.api_key,  # Example header
            "Content-Type": "application/json",
        }  # Add any other required headers, like authentication headers

        url = self.base_url + endpoint
        try:
            if method == "GET":
                response = requests.get(url, headers=headers, params=params)
            elif method == "POST":
                response = requests.post(url, headers=headers, params=params, data=json.dumps(data))
            # Add other HTTP methods as needed (PUT, DELETE)
            else:
                raise ValueError(f"Unsupported HTTP method: {method}")

            response.raise_for_status()  # Raise HTTPError for bad responses (4xx or 5xx)
            return response.json()  # Assuming the API returns JSON

        except requests.exceptions.RequestException as e:
            print(f"API request failed: {e}")
            return None

    def get_account_info(self):
        return self._make_request("account")  # Example endpoint

    def get_ticker(self, symbol):
        return self._make_request(f"ticker/{symbol}")  # Example

    def place_order(self, symbol, side, quantity, order_type="market", price=None):
        data = {"symbol": symbol, "side": side,  # "buy" or "sell"
                "quantity": quantity, "type": order_type, "price": price,  # For limit orders
                }
        return self._make_request("order", method="POST", data=data)

    def get_open_positions(self):
        return self._make_request("positions")