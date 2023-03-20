from brownie import config, accounts, network, interface

LOCAL_NETWOKRS = ["development", "mainnet-fork"]


def get_account():
    if network.show_active() in LOCAL_NETWOKRS:
        return accounts[0]
    else:
        return accounts.add(config["wallets"]["from_key"])


def approve_erc20(erc20, spender, amount):
    erc20 = interface.IERC20(erc20)
    account = get_account()
    tx = erc20.appprove(spender, amount, {"from": account})
    tx.wait(1)
    print("approved!")
