from scripts.helpful_scripts import (
    get_account,
    create_and_or_get_sub_id,
)
from brownie import RaffleV32, network, config
import os
import shutil


def main():
    deploy_lottery()
    update_front_end()


def deploy_lottery():
    account = get_account()
    vrf_contract = config["networks"][network.show_active()]["vrf_coordinator"]
    subscription_id = create_and_or_get_sub_id(account, vrf_contract)
    provider_address = config["networks"][network.show_active()]["lending_pool_addresses_provider"]
    weth = config["networks"][network.show_active()]["weth_token"]
    raffle = RaffleV32.deploy(
        vrf_contract,
        provider_address,
        weth,
        subscription_id,
        config["networks"][network.show_active()]["gasLane"],
        config["networks"][network.show_active()]["keepersUpdateInterval"],
        config["networks"][network.show_active()]["raffleEntranceFee"],
        config["networks"][network.show_active()]["callbackGasLimit"],
        {"from": account},
        publish_source=config["networks"][network.show_active()].get("verify", False),
    )
    print("Contract deployed!")
    print(f" The VRF contract address is :{vrf_contract}")
    print(f" The raffle subscription id is :{subscription_id}")
    print(f" The raffle contract address is :{raffle}")


def deploy_to_etherscan():
    contract = RaffleV32[-1]
    RaffleV32.publish_source(contract)


def enter_raffle():
    account = get_account()
    raffle = RaffleV32[-1]
    entrance_fee = config["networks"][network.show_active()]["raffleEntranceFee"]
    start_tx = raffle.enterRaffle({"from": account, "value": entrance_fee})
    start_tx.wait(1)
    print("Raffle entered")


def withdraw_player():
    account = get_account()
    contract = RaffleV32[-1]
    tx = contract.withdrawPlayer({"from": account})
    tx.wait(1)
    print("Player withdrawn!")


def get_raffle_state():
    contract = RaffleV32[-1]
    state = contract.getRaffleState()
    states = ["OPEN", "CALCULATING", "PAUSED"]
    current_state = states[state]
    print(f"Raffle state is: {current_state}")


def toggle_pause():
    get_raffle_state()
    account = get_account()
    contract = RaffleV32[-1]
    tx = contract.togglePause({"from": account})
    tx.wait(1)
    print("Changing state...")
    get_raffle_state()


def get_number_players():
    contract = RaffleV32[-1]
    players = contract.getNumberOfPlayers()
    print(f"Raffle number of players: {players}")


def get_index_of_address():
    contract = RaffleV32[-1]
    account = get_account()
    index = contract.getIndexOfAddress(account)
    print(f"index of address is: {index}")


def get_has_index():
    contract = RaffleV32[-1]
    account = get_account()
    index = contract.getHasIndex(account)
    print(f"Address has index: {index}")


def update_front_end():
    print("Updating front end...")

    # The deployments map
    copy_files_to_front_end(
        "./build/deployments/map.json",
        "../WS-lottery-fe-new/constants/contractAddresses.json",
    )

    # The contracts abi
    copy_files_to_front_end(
        "./build/contracts/RaffleV32.json",
        "../WS-lottery-fe-new/constants/abi.json",
    )

    # # The Config, converted from YAML to JSON
    # # This function loads the .yaml file into a dictionairy and dumps it into .json format  so our front_end can use it.
    # with open("brownie-config.yaml", "r") as brownie_config:
    #     config_dict = yaml.load(brownie_config, Loader=yaml.FullLoader)
    #     with open("./front_end/src/brownie-config.json", "w") as brownie_config_json:
    #         json.dump(config_dict, brownie_config_json)
    print("Front end updated!")


def copy_folders_to_front_end(scr, dest):
    # If the path already exists in front_end, then remove it.
    if os.path.exists(dest):
        shutil.rmtree(dest)
    # If it doesn't exist, copy from the build folder.
    shutil.copytree(scr, dest)


def copy_files_to_front_end(src, dest):
    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copyfile(src, dest)
