/*
Copyright 2022.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controllers

import (
	"context"
	"fmt"

	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/selection"
	"k8s.io/klog/v2"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	appv1alpha1 "github.com/pdettori/kealm/api/v1alpha1"
	clusterclient "open-cluster-management.io/api/client/cluster/clientset/versioned"
	clusterlisterv1alpha1 "open-cluster-management.io/api/client/cluster/listers/cluster/v1alpha1"
	workv1client "open-cluster-management.io/api/client/work/clientset/versioned"

	clusterapiv1alpha1 "open-cluster-management.io/api/cluster/v1alpha1"
	workapiv1 "open-cluster-management.io/api/work/v1"
)

// AppBundleReconciler reconciles a AppBundle object
type AppBundleReconciler struct {
	client.Client
	Scheme                  *runtime.Scheme
	ClusterClient           clusterclient.Interface
	PlacementLister         clusterlisterv1alpha1.PlacementLister
	PlacementDecisionLister clusterlisterv1alpha1.PlacementDecisionLister
	WorkClient              workv1client.Clientset
}

const (
	// PlacementLabel is the label to attach a placement to AppBundle
	PlacementLabel = "cluster.open-cluster-management.io/placement"
)

//+kubebuilder:rbac:groups=app.open-cluster-management.io,resources=appbundles,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=app.open-cluster-management.io,resources=appbundles/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=app.open-cluster-management.io,resources=appbundles/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the AppBundle object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.10.0/pkg/reconcile
func (r *AppBundleReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	var bundle appv1alpha1.AppBundle
	if err := r.Get(ctx, req.NamespacedName, &bundle); err != nil {
		klog.Error(err, "unable to fetch AppBundle")
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	var pLabel *string
	if pLabel = getPlacementLabel(bundle); pLabel == nil {
		klog.Infof("No placement label found on AppBundle %s", bundle.Name)
		return ctrl.Result{}, nil
	}

	klog.Infof("Placement label %s found on AppBundle %s", *pLabel, bundle.Name)
	placementDec, err := r.getPlacementDecision(*pLabel, req.Namespace)
	if err != nil {
		return ctrl.Result{}, err
	}
	klog.Infof("found %+v", placementDec.Status.Decisions)

	if err != nil {
		return ctrl.Result{}, err
	}
	err = r.scheduleBundle(bundle, placementDec)
	if err != nil {
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *AppBundleReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&appv1alpha1.AppBundle{}).
		Complete(r)
}

func getPlacementLabel(bundle appv1alpha1.AppBundle) *string {
	l, ok := bundle.GetLabels()[PlacementLabel]
	if ok {
		return &l
	}
	return nil
}

func (r *AppBundleReconciler) getPlacementDecision(placementName, placementNamespace string) (*clusterapiv1alpha1.PlacementDecision, error) {
	klog.Infof("Namespace: %s", placementNamespace)
	pReq, _ := labels.NewRequirement(PlacementLabel, selection.Equals, []string{placementName})
	selector := labels.NewSelector()
	selector = selector.Add(*pReq)
	pList, err := r.PlacementDecisionLister.PlacementDecisions(placementNamespace).List(selector)
	if err != nil {
		return nil, err
	}
	if len(pList) >= 1 {
		return pList[0], nil
	}
	return nil, fmt.Errorf("Could not find placement decision for placement %s ", placementName)
}

func (r *AppBundleReconciler) scheduleBundle(bundle appv1alpha1.AppBundle, decision *clusterapiv1alpha1.PlacementDecision) error {
	for _, dec := range decision.Status.Decisions {
		klog.Infof("Generating manifest for cluster %s", dec.ClusterName)
		manifest := generateManifest(bundle, dec.ClusterName)

		klog.Infof("Applying manifest for cluster %s", dec.ClusterName)

		_, err := r.WorkClient.WorkV1().ManifestWorks(dec.ClusterName).Create(context.TODO(), manifest, v1.CreateOptions{})

		if err != nil {
			return err
		}
	}
	return nil
}

func generateManifest(bundle appv1alpha1.AppBundle, namespace string) *workapiv1.ManifestWork {
	manifest := &workapiv1.ManifestWork{
		TypeMeta: v1.TypeMeta{
			Kind:       "ManifestWork",
			APIVersion: workapiv1.GroupVersion.Version,
		},
		ObjectMeta: v1.ObjectMeta{
			Name:        bundle.Name,
			Namespace:   bundle.Namespace,
			Labels:      bundle.Labels,
			Annotations: bundle.Annotations,
		},
		Spec: bundle.Spec,
	}
	manifest.Namespace = namespace
	return manifest
}
