from brownie import Strategy, network, config, accounts, interface


weth = config["networks"][network.show_active()]["weth"]
dai = config["networks"][network.show_active()]["dai"]
eth_oracle = config["networks"][network.show_active()]["eth_oracle"]
dai_oracle = config["networks"][network.show_active()]["dai_oracle"]
lendingPoolAddressProvider = config["networks"][network.show_active()][
    "lending_pool_address_provider"
]
amount = 1 * 10**18


def deploy():
    account = get_account()
    Strategy.deploy(
        weth,
        dai,
        eth_oracle,
        dai_oracle,
        lendingPoolAddressProvider,
        {"from": account},
        publish_source=config["networks"][network.show_active()]["publish_source"],
    )


def depositETH():
    strategy = Strategy[-1]
    account = get_account()
    tx1 = strategy.depositETH({"from": account, "value": amount})
    tx1.wait(1)
    tx2 = strategy.getWethBalance({"from": account})
    print(f"weth_balance = {tx2}")
    tx3 = strategy.depositWeth(amount, {"from": account})
    tx3.wait(1)
    tx4 = strategy.getWethBalance({"from": account})
    print(f"weth_balance = {tx4}")
    tx5 = strategy.borrowDai(amount, {"from": account})
    tx5.wait(1)
    print("borrowed DAI!")


def main():
    deploy()
    depositETH()


LOCAL_NETWOKRS = ["development", "mainnet-fork"]


def get_account():
    if network.show_active() in LOCAL_NETWOKRS:
        return accounts[0]
    else:
        return accounts.add(config["wallets"]["from_key"])
