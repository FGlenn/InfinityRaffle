from scripts.helpful_scripts import get_account
from brownie import YieldAggregatorV32, network, config
from web3 import Web3


def main():
    # deploy_yield_aggregator()
    # enter()
    withdraw()


def enter():
    get_user_account_data()
    get_total_deposited()
    get_total_players()
    enter_player()
    get_user_account_data()
    get_total_deposited()
    get_total_players()


def withdraw():
    get_total_players()
    get_yield_bal()
    get_total_deposited()
    withdraw_player()
    get_total_players()
    get_yield_bal()
    get_user_account_data()
    get_total_deposited()


def deploy_yield_aggregator():
    account = get_account()
    provider_address = config["networks"][network.show_active()][
        "lending_pool_addresses_provider"
    ]
    weth = config["networks"][network.show_active()]["weth_token"]
    YieldAggregatorV32.deploy(provider_address, weth, {"from": account})
    print("Contract deployed!")


def enter_player():
    account = get_account()
    value = 10000000000000000
    contract = YieldAggregatorV32[-1]
    tx = contract.enterPlayer({"value": value, "from": account})
    tx.wait(1)
    print("Player entered!")


def withdraw_player():
    account = get_account()
    contract = YieldAggregatorV32[-1]
    tx = contract.withdrawPlayer({"from": account})
    tx.wait(1)
    print("Player withdrawn!")
    get_total_deposited()


def get_yield_bal():
    contract = YieldAggregatorV32[-1]
    bal = contract.getYieldBalance()
    print(f"Yield balance is:{bal}")


def get_user_account_data():
    contract = YieldAggregatorV32[-1]
    total_collateral = contract.getUserAccountData()
    print(f"Total colleteral:{total_collateral}")


def get_total_deposited():
    contract = YieldAggregatorV32[-1]
    total_deposited = contract.getTotalDeposited()
    print(f"Total deposited in contract:{total_deposited}")


def get_player_deposited():
    contract = YieldAggregatorV32[-1]
    address = "0x6c7Ea729bfDDA50aA0A0Dc3E12FECC1bBAc28472"
    total_deposited = contract.getPlayerDeposited(address)
    print(f"Player deposited in contract:{total_deposited}")
    address = "0x563b06a204495AA31c5c2D9fd6C1360d902d5b1C"
    total_deposited = contract.getPlayerDeposited(address)
    print(f"Player deposited in contract:{total_deposited}")


def get_total_players():
    contract = YieldAggregatorV32[-1]
    total_players = contract.getNumberOfPlayers()
    print(f"Total players in contract:{total_players}")


def get_index_of_player():
    contract = YieldAggregatorV32[-1]
    address = "0x6c7Ea729bfDDA50aA0A0Dc3E12FECC1bBAc28472"
    index = contract.getIndexOfAddress(address)
    print(f"Index of player is:{index}")
    address = "0x563b06a204495AA31c5c2D9fd6C1360d902d5b1C"
    index = contract.getIndexOfAddress(address)
    print(f"Index of player is:{index}")


def get_address_at_index():
    contract = YieldAggregatorV32[-1]
    index = "0"
    address = contract.getAddressAtIndex(index)
    print(f"Address of index 0 is:{address}")
    index = "1"
    address = contract.getAddressAtIndex(index)
    print(f"Address of index 1 is:{address}")
