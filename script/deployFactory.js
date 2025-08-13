const {ethers} = require("hardhat");

async function main() {
    const SUBSCRIPTION_ID = 90516499838097632136265761760469201502637847315309462758122770229382549458681;

    const Factory = await ethers.getContractFactory("LotteryFactory");
    const factory = await Factory.deploy(SUBSCRIPTION_ID);
    await factory.deployed();

}