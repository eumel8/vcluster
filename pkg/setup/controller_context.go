package setup

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/loft-sh/vcluster/pkg/config"
	"github.com/loft-sh/vcluster/pkg/controllers/resources/nodes"
	"github.com/loft-sh/vcluster/pkg/plugin"
	"github.com/loft-sh/vcluster/pkg/pro"
	"github.com/loft-sh/vcluster/pkg/telemetry"
	"github.com/loft-sh/vcluster/pkg/util/blockingcacheclient"
	"github.com/loft-sh/vcluster/pkg/util/translate"
	"github.com/pkg/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	clientcmdapi "k8s.io/client-go/tools/clientcmd/api"
	"k8s.io/klog/v2"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"
)

// NewControllerContext builds the controller context we can use to start the syncer
func NewControllerContext(
	ctx context.Context,
	options *config.VirtualClusterConfig,
	currentNamespace string,
	inClusterConfig *rest.Config,
	scheme *runtime.Scheme,
) (*config.ControllerContext, error) {
	// create controller context
	controllerContext, err := InitManagers(
		ctx,
		options,
		currentNamespace,
		inClusterConfig,
		scheme,
		pro.NewPhysicalClient(options),
		pro.NewVirtualClient(options),
	)
	if err != nil {
		return nil, err
	}

	// init pro controller context
	err = pro.InitProControllerContext(controllerContext)
	if err != nil {
		return nil, err
	}

	return controllerContext, nil
}

func InitManagers(
	ctx context.Context,
	options *config.VirtualClusterConfig,
	currentNamespace string,
	inClusterConfig *rest.Config,
	scheme *runtime.Scheme,
	newPhysicalClient client.NewClientFunc,
	newVirtualClient client.NewClientFunc,
) (*config.ControllerContext, error) {
	// load virtual config
	virtualConfig, virtualRawConfig, err := LoadVirtualConfig(ctx, options)
	if err != nil {
		return nil, err
	}

	// is multi namespace mode?
	var defaultNamespaces map[string]cache.Config
	if options.Experimental.MultiNamespaceMode.Enabled {
		// set options.TargetNamespace to empty because it will later be used in Manager
		options.TargetNamespace = ""
		translate.Default = translate.NewMultiNamespaceTranslator(currentNamespace)
	} else {
		// ensure target namespace
		if options.TargetNamespace == "" {
			options.TargetNamespace = currentNamespace
		}
		translate.Default = translate.NewSingleNamespaceTranslator(options.TargetNamespace)
		defaultNamespaces = map[string]cache.Config{options.TargetNamespace: {}}
	}

	// start plugins
	err = StartPlugins(ctx, currentNamespace, inClusterConfig, virtualConfig, virtualRawConfig, options)
	if err != nil {
		return nil, err
	}

	// create physical manager
	klog.Info("Using physical cluster at " + inClusterConfig.Host)
	localManager, err := ctrl.NewManager(inClusterConfig, ctrl.Options{
		Scheme:         scheme,
		Metrics:        metricsserver.Options{BindAddress: "0"},
		LeaderElection: false,
		Cache:          cache.Options{DefaultNamespaces: defaultNamespaces},
		NewClient:      newPhysicalClient,
	})
	if err != nil {
		return nil, err
	}

	// create virtual manager
	virtualClusterManager, err := ctrl.NewManager(virtualConfig, ctrl.Options{
		Scheme:         scheme,
		Metrics:        metricsserver.Options{BindAddress: "0"},
		LeaderElection: false,
		NewClient:      newVirtualClient,
	})
	if err != nil {
		return nil, err
	}

	// init controller context
	return InitControllerContext(ctx, currentNamespace, localManager, virtualClusterManager, virtualRawConfig, options)
}

func StartPlugins(
	ctx context.Context,
	currentNamespace string,
	inClusterConfig,
	virtualConfig *rest.Config,
	virtualRawConfig *clientcmdapi.Config,
	options *config.VirtualClusterConfig,
) error {
	klog.Infof("Start Plugins Manager...")
	syncerConfig, err := CreateVClusterKubeConfig(virtualRawConfig, options)
	if err != nil {
		return err
	}

	err = plugin.DefaultManager.Start(ctx, currentNamespace, options.TargetNamespace, virtualConfig, inClusterConfig, syncerConfig, options)
	if err != nil {
		return err
	}

	return nil
}

func LoadVirtualConfig(ctx context.Context, options *config.VirtualClusterConfig) (*rest.Config, *clientcmdapi.Config, error) {
	// wait for client config
	clientConfig, err := WaitForClientConfig(ctx, options)
	if err != nil {
		return nil, nil, err
	}

	virtualClusterConfig, err := clientConfig.ClientConfig()
	if err != nil {
		return nil, nil, err
	}

	// We increase the limits here so that we don't get any problems
	virtualClusterConfig.QPS = 1000
	virtualClusterConfig.Burst = 2000
	virtualClusterConfig.Timeout = 0

	// start leader election for controllers
	rawConfig, err := clientConfig.RawConfig()
	if err != nil {
		return nil, nil, err
	}

	return virtualClusterConfig, &rawConfig, nil
}

func WaitForClientConfig(ctx context.Context, options *config.VirtualClusterConfig) (clientcmd.ClientConfig, error) {
	// wait until kube config is available
	var clientConfig clientcmd.ClientConfig
	err := wait.PollUntilContextTimeout(ctx, time.Second, time.Hour, true, func(ctx context.Context) (bool, error) {
		out, err := os.ReadFile(options.VirtualClusterKubeConfig().KubeConfig)
		if err != nil {
			if os.IsNotExist(err) {
				klog.Info("couldn't find virtual cluster kube-config, will retry in 1 seconds")
				return false, nil
			}

			return false, err
		}

		// parse virtual cluster config
		clientConfig, err = clientcmd.NewClientConfigFromBytes(out)
		if err != nil {
			return false, errors.Wrap(err, "read kube config")
		}

		restConfig, err := clientConfig.ClientConfig()
		if err != nil {
			return false, errors.Wrap(err, "read kube client config")
		}

		kubeClient, err := kubernetes.NewForConfig(restConfig)
		if err != nil {
			return false, errors.Wrap(err, "create kube client")
		}

		_, err = kubeClient.Discovery().ServerVersion()
		if err != nil {
			klog.Infof("couldn't retrieve virtual cluster version (%v), will retry in 1 seconds", err)
			return false, nil
		}
		_, err = kubeClient.CoreV1().ServiceAccounts("default").Get(ctx, "default", metav1.GetOptions{})
		if err != nil {
			klog.Infof("default ServiceAccount is not available yet, will retry in 1 seconds")
			return false, nil
		}

		telemetry.Collector.SetVirtualClient(kubeClient)
		return true, nil
	})
	if err != nil {
		return nil, err
	}

	return clientConfig, nil
}

func CreateVClusterKubeConfig(config *clientcmdapi.Config, options *config.VirtualClusterConfig) (*clientcmdapi.Config, error) {
	config = config.DeepCopy()

	// exchange kube config server & resolve certificate
	for i := range config.Clusters {
		// fill in data
		if config.Clusters[i].CertificateAuthorityData == nil && config.Clusters[i].CertificateAuthority != "" {
			o, err := os.ReadFile(config.Clusters[i].CertificateAuthority)
			if err != nil {
				return nil, err
			}

			config.Clusters[i].CertificateAuthority = ""
			config.Clusters[i].CertificateAuthorityData = o
		}

		if options.Config.ExportKubeConfig.Server != "" {
			config.Clusters[i].Server = options.Config.ExportKubeConfig.Server
		} else {
			config.Clusters[i].Server = fmt.Sprintf("https://localhost:%d", options.Config.ControlPlane.Proxy.Port)
		}
	}

	// resolve auth info cert & key
	for i := range config.AuthInfos {
		// fill in data
		if config.AuthInfos[i].ClientCertificateData == nil && config.AuthInfos[i].ClientCertificate != "" {
			o, err := os.ReadFile(config.AuthInfos[i].ClientCertificate)
			if err != nil {
				return nil, err
			}

			config.AuthInfos[i].ClientCertificate = ""
			config.AuthInfos[i].ClientCertificateData = o
		}
		if config.AuthInfos[i].ClientKeyData == nil && config.AuthInfos[i].ClientKey != "" {
			o, err := os.ReadFile(config.AuthInfos[i].ClientKey)
			if err != nil {
				return nil, err
			}

			config.AuthInfos[i].ClientKey = ""
			config.AuthInfos[i].ClientKeyData = o
		}
	}

	return config, nil
}

func InitControllerContext(
	ctx context.Context,
	currentNamespace string,
	localManager,
	virtualManager ctrl.Manager,
	virtualRawConfig *clientcmdapi.Config,
	vClusterOptions *config.VirtualClusterConfig,
) (*config.ControllerContext, error) {
	stopChan := make(<-chan struct{})

	// get virtual cluster version
	discoveryClient, err := discovery.NewDiscoveryClientForConfig(virtualManager.GetConfig())
	if err != nil {
		return nil, errors.Wrap(err, "create discovery client")
	}
	virtualClusterVersion, err := discoveryClient.ServerVersion()
	if err != nil {
		return nil, errors.Wrap(err, "get virtual cluster version")
	}
	nodes.FakeNodesVersion = virtualClusterVersion.GitVersion
	klog.Infof("Can connect to virtual cluster with version " + virtualClusterVersion.GitVersion)

	// create a new current namespace client
	currentNamespaceClient, err := NewCurrentNamespaceClient(ctx, currentNamespace, localManager, vClusterOptions)
	if err != nil {
		return nil, err
	}

	localDiscoveryClient, err := discovery.NewDiscoveryClientForConfig(localManager.GetConfig())
	if err != nil {
		return nil, err
	}

	err = vClusterOptions.DisableMissingAPIs(localDiscoveryClient)
	if err != nil {
		return nil, err
	}

	return &config.ControllerContext{
		Context:               ctx,
		LocalManager:          localManager,
		VirtualManager:        virtualManager,
		VirtualRawConfig:      virtualRawConfig,
		VirtualClusterVersion: virtualClusterVersion,

		CurrentNamespace:       currentNamespace,
		CurrentNamespaceClient: currentNamespaceClient,

		StopChan: stopChan,
		Config:   vClusterOptions,
	}, nil
}

func NewCurrentNamespaceClient(ctx context.Context, currentNamespace string, localManager ctrl.Manager, options *config.VirtualClusterConfig) (client.Client, error) {
	var err error

	// currentNamespaceCache is needed for tasks such as finding out fake kubelet ips
	// as those are saved as Kubernetes services inside the same namespace as vcluster
	// is running. In the case of options.TargetNamespace != currentNamespace (the namespace
	// where vcluster is currently running in), we need to create a new object cache
	// as the regular cache is scoped to the options.TargetNamespace and cannot return
	// objects from the current namespace.
	currentNamespaceCache := localManager.GetCache()
	if currentNamespace != options.TargetNamespace {
		currentNamespaceCache, err = cache.New(localManager.GetConfig(), cache.Options{
			Scheme:            localManager.GetScheme(),
			Mapper:            localManager.GetRESTMapper(),
			DefaultNamespaces: map[string]cache.Config{currentNamespace: {}},
		})
		if err != nil {
			return nil, err
		}
	}

	// start cache now if it's not in the same namespace
	if currentNamespace != options.TargetNamespace {
		go func() {
			err := currentNamespaceCache.Start(ctx)
			if err != nil {
				panic(err)
			}
		}()
		currentNamespaceCache.WaitForCacheSync(ctx)
	}

	// create a current namespace client
	currentNamespaceClient, err := blockingcacheclient.NewCacheClient(localManager.GetConfig(), client.Options{
		Scheme: localManager.GetScheme(),
		Mapper: localManager.GetRESTMapper(),
		Cache: &client.CacheOptions{
			Reader: currentNamespaceCache,
		},
	})
	if err != nil {
		return nil, err
	}

	return currentNamespaceClient, nil
}
