# Argo Ingress controller

Argo ingress controller is ingress controller that uses cloudflare argo for
ingress. For more informations regarding argo [take a look here](https://blog.cloudflare.com/argo/).

One of the major things why argo is usefull is because you don't have to configure
load balancers, DNS entries, SSL certs and other things related to exposing
your service to the internet. You just enable argo and it provides a tunnel
from your kubernetes cluster to cloudflare, configures DNS entries, load
balancing and SSL for you. If using [cloudflare access](https://blog.cloudflare.com/introducing-cloudflare-access/)
it also provides SSO for all your internal sites using different IDp providers.

## Usage

### Create argo certificate for your domain

First you will need to [download cloudflared](https://developers.cloudflare.com/argo-tunnel/downloads/).
After you have done that you can login to cloudflare using:

```bash
cloudflared login
```

It will save you certificate to `~/.cloudflared/cert.pem`.

### Create secret

You will need to create secret with content of downloaded domain:

```
kubectl create secret generic cloudflared-cert --from-file=cert.pem=$HOME/.cloudflared/cert.pem 
```

### Configure `argo-ingress-controller`

Use the following example config to deploy `argo-ingress-controller`

```
  kubernetes.modules.argo-ingress-controller = {
    module = "argo-ingress-controller";
  };
```

### Configure your service and ingress

```
  kubernetes.modules.nginx = {
    module = "nginx";
  };

  kubernetes.resources.ingresses.nginx-ingress = {
    metadata.annotations."kubernetes.io/ingress.class" = "argo-tunnel";
    spec.rules = [{
      host = "nginx.x-truder.net";
      http.paths = [{
        path = "/";
        backend = {
          serviceName = "nginx";
          servicePort = 80;
        };
      }];
    }];
  };
```

At this point dns entry will automatically be created in cloudflare and tunnel will
be made. You can additionally configure cloudflare access to limit access your
resources.
