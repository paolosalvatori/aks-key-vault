## External Secrets Operator with Azure Key Vault

The [External Secrets Operator](https://external-secrets.io/latest/) is a Kubernetes operator that enables managing secrets stored in external secret stores, such as Azure Key Vault, AWS Secret Manager, and Google Key Management, and Hashicorp Vault.. It leverages the Azure Key Vault provider to synchronize secrets into Kubernetes secrets for easy consumption by applications. External Secrets Operator integrates with [Azure Key vault](https://azure.microsoft.com/services/key-vault/) for secrets, certificates and Keys management.

![External Secrets Operator and Key Vault](../../images/eso-az-kv-azure-kv.png)

You can configure the [External Secrets Operator](https://external-secrets.io/latest/) to use [Microsoft Entra Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-overview) to access an [Azure Key Vault](https://learn.microsoft.com/azure/key-vault/general/basic-concepts) resource.

### Advantages

- Manages secrets stored in external secret stores like Azure Key Vault, AWS Secret Manager, and Google Key Management, Hashicorp Vault, and more.
- Provides synchronization of Key Vault secrets into Kubernetes secrets.
- Simplifies secret management with Kubernetes-native integration.

### Disadvantages

- Requires setting up and managing the External Secrets Operator.

## Hands-On Lab Prerequisites

### Configure Variables

The first step is setting up the name for a new or existing AKS cluster and Azure Key Vault resource in the [`scripts/00-variables.sh`](../../scripts/00-variables.sh) file, which is included and used by all the scripts in this sample.

The `SECRETS` array variable contains a list of secrets to create in the Azure Key Vault resource, while the `VALUES` array contains their values. 

### Create or Update AKS Cluster

You can use Bash script, [`01-create-or-update-aks.sh`](../../scripts/prerequisites/01-create-or-update-aks.sh), to create a new AKS cluster with the [az aks create](https://learn.microsoft.com/cli/azure/aks?view=azure-cli-latest#az-aks-create) command. This script includes the `--enable-oidc-issuer` parameter to enable the [OpenID Connect (OIDC) issuer](https://learn.microsoft.com/azure/aks/use-oidc-issuer) and the `--enable-workload-identity` parameter to enable [Microsoft Entra Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-overview). If the AKS cluster already exists, the script updates it to use the OIDC issuer and enable workload identity by calling the [az aks update](https://learn.microsoft.com/cli/azure/aks?view=azure-cli-latest#az-aks-update) command with the same parameters.

### Create or Update Key Vault

You can use Bash script, [`02-create-key-vault-and-secrets.sh`](../../scripts/prerequisites/02-create-key-vault-and-secrets.sh), to create a new [Azure Key Vault](https://learn.microsoft.com/azure/key-vault/general/basic-concepts) if it doesn't already exist, and create a couple of secrets for demonstration purposes.

### Create Managed Identity and Federated Identity Credential

All the techniques use [Microsoft Entra Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-overview). The repository contains a folder for each technique. Each folder includes Bash script, [`create-managed-identity.sh`](../../scripts/external-secrets-operator/02-create-managed-identity.sh).

The Bash script performs the following steps:

- It sources variables from two files: [`scripts/00-variables.sh`](../../scripts/00-variables.sh) and [`scripts/external-secrets-operator/00-variables.sh`](../../scripts/external-secrets-operator/00-variables.sh) .
- It checks if the specified resource group exists. If not, it creates the resource group.
- It checks if the specified managed identity exists within the resource group. If not, it creates a user-assigned managed identity.
- It retrieves the `principalId` and `clientId` of the managed identity.
- It retrieves the `id` of the Azure Key Vault resource.
- It assigns the `Key Vault Secrets User` role to the managed identity with the Azure Key Vault as the scope.
- It checks if the specified Kubernetes namespace exists. If not, it creates the namespace.
- It checks if a specified Kubernetes service account exists within the namespace. If not, it creates the service account with the annotations and labels required by [Microsoft Entra Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-overview).
- It checks if a specified federated identity credential exists within the resource group. If not, it retrieves the OIDC Issuer URL of the specified AKS cluster and creates the federated identity credential.

## Hands-On Lab: External Secrets Operator with Azure Key Vault

In this sectioon you will see the steps to configure the [External Secrets Operator](https://external-secrets.io/latest/) to use [Microsoft Entra Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-overview) to access an [Azure Key Vault](https://learn.microsoft.com/azure/key-vault/general/basic-concepts) resource. You can install the operator to your AKS cluster using Helm, as shown in Bash script, [`01-install-external-secrets.sh`](../../scripts/external-secrets-operator/01-install-external-secrets.sh).

Then, you can create a user-assigned managed identity for the workload, create federated credentials, and assign the proper permissions to it to read secrets from the source Key Vault using the [`02-create-managed-identity.sh`](../../scripts/external-secrets-operator/02-create-managed-identity.sh) Bash script.

Next, you can run Bash script, [`03-create-secret-store.sh`](../../scripts/external-secrets-operator/03-create-secret-store.sh), to retrieve the `vaultUri` of your Key Vault resource and create a secret store custom resource. The YAML manifest of the secret store assigns the following values to the properties of the `azurekv` provider for Key Vault:

- `authType`: `WorkloadIdentity` configures the provider to utilize user-assigned managed identity with the proper permissions to access Key Vault.
- `vaultUrl`: Specifies the `vaultUri` Key Vault endpoint URL.
- `serviceAccountRef.name`: specifies the Kubernetes service account in the workload namespace that is federated with the user-assigned managed identity.

For more information on secret stores for Key Vault, see [Azure Key Vault](https://external-secrets.io/latest/provider/azure-key-vault/) in the official documentation of the External Secrets Operator.

Azure Key Vault manages different object types. The External Secrets Operator supports `keys`, `secrets`, and `certificates`. Simply prefix the key with `key`, `secret`, or `cert` to retrieve the desired type (defaults to secret).

| Object Type   | Return Value                                                 |
| :------------ | :----------------------------------------------------------- |
| `secret`      | The raw secret value.                                        |
| `key`         | A JWK which contains the public key. Azure Key Vault does not export the private key. |
| `certificate` | The raw CER contents of the x509 certificate. |

You can create one or more `ExternalSecret` objects in your workload namespace to read `keys`, `secrets`, and `certificates` from Key Vault. To create a Kubernetes secret from the Azure Key Vault secret, you need to use `Kind=ExternalSecret`. You can retrieve keys, secrets, and certificates stored inside your Key Vault by setting a `/` prefixed type in the secret name. The default type is `secret`, but other supported values are `cert` and `key`. The Bash script, [`04-create-secrets.sh`](../../scripts/external-secrets-operator/04-create-secrets.sh), creates an `ExternalSecret` object configured to reference the secret store created in the previous step. The `ExternalSecret` object has two sections:

- `dataFrom`: This section contains a `find` element that uses regular expressions to retrieve any secret whose `name` starts with `user`. For each secret, the Key Vault provider will create a key-value mapping in the `data` section of the Kubernetes secret using the name and value of the corresponding Key Vault secret.
- `data`: This section specifies the explicit type and name of the secrets, keys, and certificates to retrieve from Key Vault. In this sample, it tells the Key Vault provider to create a key-value mapping in the `data` section of the Kubernetes secret for the `password` Key Vault secret, using `password` as the key.

For more information on external secrets, see [Azure Key Vault](https://external-secrets.io/latest/provider/azure-key-vault/) in the official documentation of the External Secrets Operator.

Finally, you can run Bash script, [`05-get-secrets.sh`](../../scripts/external-secrets-operator/05-get-secrets.sh), to print the key-value mappings contained in the Kubernetes secret created by the External Secrets Operator.

## Conclusion

[External Secrets Operator](https://external-secrets.io/latest/) can be summarized as follows:
  - Manages secrets stored in external secret stores like Azure Key Vault, AWS Secret Manager, and Google Key Management, Hashicorp Vault, and more.
  - Provides synchronization of Key Vault secrets into Kubernetes secrets.
  - Simplifies secret management with Kubernetes-native integration.

## Resources

- [External Secrets Operator](https://external-secrets.io/latest/)
- [Azure Key Vault Provider for External Secrets Operator](https://external-secrets.io/latest/provider/azure-key-vault/)