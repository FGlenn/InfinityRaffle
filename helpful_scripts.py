from brownie import (
    accounts,
    network,
    config,
    # VRFCoordinatorV2Mock,
    Contract,
    # LinkToken,
    # VRFCoordinatorMock,
    # MockV3Aggregator,
)


FORKED_LOCAL_ENVIRONMENTS = ["mainnet-fork", "mainnet-fork-dev"]
LOCAL_BLOCKCHAIN_ENVIRONMENTS = ["development", "ganache-local"]


def get_account(index=None, id=None):
    # accounts[0]
    # accounts.add("env")
    # accounts.load("id")
    if index:
        return accounts[index]
    if id:
        return accounts.load(id)
    if (
        network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS
        or network.show_active() in FORKED_LOCAL_ENVIRONMENTS
    ):
        return accounts[0]
    return accounts.add(config["wallets"]["from_key"])


# This mapping matches contract names to their types
# contract_to_mock = {
#     "eth_usd_price_feed": MockV3Aggregator,
#     "vrf_coordinator": VRFCoordinatorMock,
#     "link_token": LinkToken,
# }


def get_contract(contract_name):
    """This function will grab the contract addresses from the brownie config
    if defined, otherwise, it will deploy a mock version of that contract, and
    return that mock contract.
        Args:
            contract_name (string)
        Returns:
            brownie.network.contract.ProjectContract: The most recently deployed
            version of this contract.
    """
    # "contract_type" gives MockV3Aggregator if "contract_name" is "eth_usd_price_feed"     from mapping "contract_to_mock"
    # "contract_type" gives VRFCoordinatorV2Mock if "contract_name" is "vrfCoordinatorV2"      from mapping "contract_to_mock"
    # "contract_type" gives LinkToken if "contract_name" is "link_token"                    from mapping "contract_to_mock"
    # "if len(contract_type)" = MockV3Aggregator.length. If it isn't empty/zero, deploy mocks
    # "contract_type[-1]" is similar as "MockV3Aggregator[-1]"
    #
    # Get the "contract_address" based on the "contract_name" in config.
    # E.g. "config["networks"][network.show_active()][eth_usd_price_feed]" = "0x8A753747A1Fa494EC906cE90E9f37563A8AF630e"
    # Get the "contract_type.abi" based on the "contract_address" and combine data as "contract".
    # E.g. Get the "MockV3Aggregator.abi" based on "0x8A753747A1Fa494EC906cE90E9f37563A8AF630e" gives "contract".
    contract_type = contract_to_mock[contract_name]
    if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        if len(contract_type) <= 0:
            deploy_mocks()
        contract = contract_type[-1]
    else:
        contract_address = config["networks"][network.show_active()][contract_name]
        contract = Contract.from_abi(
            contract_type._name, contract_address, contract_type.abi
        )
    return contract


# This function checks which network is used to deploy the contract to.
# If the contract is deployed to a local network, get the VRF mock contract and create ID.
# If the contract is not deployed on a local network, get the ID from brownie-config.
def create_and_or_get_sub_id(account, vrf_contract):
    if network.show_active() in LOCAL_BLOCKCHAIN_ENVIRONMENTS:
        contract_address = vrf_contract
        sub_tx = contract_address.createSubscription({"from": account})
        sub_tx.wait(1)
        print("Subscription created!")
        subscription_id = sub_tx.events[-1]["subId"]
        print(f"Subscription ID is :{subscription_id}")
        amount = 10000000000000000  # =0.01ETH
        fund_sub_tx = contract_address.fundSubscription(
            subscription_id, amount, {"from": account}
        )
        fund_sub_tx.wait(1)
        old_balance = fund_sub_tx.events[-1]["oldBalance"]
        new_balance = fund_sub_tx.events[-1]["newBalance"]
        print(f" The old balance of subscription was: {old_balance}")
        print(f" The old balance of subscription was: {new_balance}")
        print("Subscription funded!")
    else:
        subscription_id = config["networks"][network.show_active()]["subscriptionId"]
    return subscription_id


# "VRFCoordinatorMock" additionaly requires "base_fee" and "gas_price_link" as requirements for deployment. Which is the "link_token" mock's address.
def deploy_mocks():
    account = get_account()
    print("Link token mock deployed!")
    base_fee = config["networks"][network.show_active()]["baseFee"]
    gas_price_link = config["networks"][network.show_active()]["gasPriceLink"]
    # VRFCoordinatorV2Mock.deploy(base_fee, gas_price_link, {"from": account})
    print("VRF coordinator mock deployed!")
    print("All mocks deployed!")


# 0.1 LINK fee
# "account = account" use the account set in the "def fund_with_link" argument (account=None here)
# "if account" meaning, if it exists. Otherwise use the "get_account()" function
# "link_token = link_token" use the account set in the "def fund_with_link" argument (link_token=None here)
# "if link_token" meaning, if it exists. Otherwise use the "get_contract("link_token")" function
# def fund_with_link(
#     contract_address, account=None, link_token=None, amount=100000000000000000
# ):
#     account = account if account else get_account()
#     link_token = link_token if link_token else get_contract("link_token")
#     tx = link_token.transfer(contract_address, amount, {"from": account})
#     # link_token_contract = interface.LinkTokenInterface(link_token.address)
#     # tx = link_token_contract.transfer(contract_address, amount, {"from": account})
#     tx.wait(1)
#     print("Fund contract!")
#     return tx


# Two ways to get an existing contract
#
# 1: get_contract("link_token")
# contract_address = config["networks"][network.show_active()][contract_name]
# contract = Contract.from_abi(
# contract_type._name, contract_address, contract_type.abi
#
# 2: link_token_contract = interface.LinkTokenInterface(link_token.address)
# tx = link_token_contract.transfer(contract_address, amount, {"from": account})
