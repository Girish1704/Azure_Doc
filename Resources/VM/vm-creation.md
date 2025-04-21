# 🖥️ Creating a Virtual Machine in Azure: Complete Guide

Welcome to this complete guide on how to create a Virtual Machine (VM) in Microsoft Azure using various methods.

---

## 📚 Table of Contents

- [📌 Introduction](#-introduction)
- [🛠️ Prerequisites](#-prerequisites)
- [1️⃣ Using Azure Portal (GUI)](#-1-using-azure-portal-gui)
- [2️⃣ Using Azure CLI](#-2-using-azure-cli)
- [3️⃣ Using PowerShell](#-3-using-powershell)
- [4️⃣ Using ARM Templates](#-4-using-arm-templates)
- [5️⃣ Using Bicep](#-5-using-bicep)
- [📄 Conclusion](#-conclusion)
- [📎 References](#-references)

---

## 📌 Introduction

Creating a Virtual Machine (VM) in Azure can be done using multiple methods depending on the user’s preference, use case, and level of automation required. This guide will walk you through **all the major methods** with step-by-step instructions and screenshots/code examples.

## 🛠️ Prerequisites

- An active **Azure Subscription**
- Basic knowledge of Azure services
- Access to [Azure Portal](https://portal.azure.com/)
- Azure CLI or PowerShell installed for CLI methods
- VS Code (optional) for template-based deployment
---

## 1️⃣ Using Azure Portal (GUI)

Creating a VM via Azure Portal is the most user-friendly method, especially for beginners. It provides a step-by-step UI for setting up your VM.

### 🪜 Steps to Create a VM via Portal:

1. **Login** to [Azure Portal](https://portal.azure.com/)
2. In the search bar, type **"Virtual Machines"** and select it.
3. Click on **“+ Create”** → **“Azure virtual machine”**

   ![Create VM](https://learn.microsoft.com/en-us/azure/virtual-machines/media/windows/quick-create-portal/overview.png)

4. **Basics tab**: Fill in the following details:
   - **Subscription**: Choose your subscription
   - **Resource Group**: Create new or use existing
   - **Virtual machine name**: e.g., `MyVM`
   - **Region**: Select a nearby region (e.g., Central India)
   - **Image**: Choose OS (e.g., Windows Server 2022)
   - **Size**: Click “Change size” and select preferred VM size
   - **Username & Password**: Set admin credentials

5. **Disks tab**: Choose Standard SSD or Premium SSD depending on performance needs.

6. **Networking tab**: 
   - Keep defaults or create a new virtual network and subnet
   - Select “Public IP” to allow internet access

7. **Management, Monitoring, and Advanced**: Leave default (optional settings)

8. **Review + create**: Validate your settings

   ![Review and Create](https://learn.microsoft.com/en-us/azure/virtual-machines/media/windows/quick-create-portal/review-create.png)

9. Click **Create** to deploy your VM 🎉

### 🧠 Tips:
- You can use **Tags** to organize your VM
- Use **Availability Zones** for redundancy
- Enable **Boot diagnostics** under Monitoring tab for debugging

---

✅ Once deployed, you’ll see the VM listed in your “Virtual Machines” section. Click on it to view the dashboard and connect via RDP or SSH.

