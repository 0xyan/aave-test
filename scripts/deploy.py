from brownie import Strategy, network, config, accounts, interface


weth = config["networks"][network.show_active()]["weth"]
dai = config["networks"][network.show_active()]["dai"]
eth_oracle = config["networks"][network.show_active()]["eth_oracle"]
dai_oracle = config["networks"][network.show_active()]["dai_oracle"]
lendingPoolAddressProvider = config["networks"][network.show_active()][
    "lending_pool_address_provider"
]
dai_debt = config["networks"][network.show_active()]["aave_dai_debt_token"]
amount = 1 * 10**18


def deploy():
    account = get_account()
    Strategy.deploy(
        weth,
        dai,
        eth_oracle,
        dai_oracle,
        lendingPoolAddressProvider,
        dai_debt,
        {"from": account},
        publish_source=config["networks"][network.show_active()]["publish_source"],
    )


def depositETH():
    strategy = Strategy[-1]
    account = get_account()
    tx1 = strategy.depositETH({"from": account, "value": amount})
    tx1.wait(1)
    tx2 = strategy.depositWeth({"from": account})
    print("borrowed DAI!")
    tx2 = strategy.withdrawFromUni({"from": account})
    tx2.wait(1)
    tx3 = strategy.withdrawAll()
    tx3.wait(1)


def main():
    deploy()
    depositETH()


LOCAL_NETWOKRS = ["development", "mainnet-fork"]


def get_account():
    if network.show_active() in LOCAL_NETWOKRS:
        return accounts[0]
    else:
        return accounts.add(config["wallets"]["from_key"])
