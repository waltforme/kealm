/*
Copyright 2021.

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

	"github.com/go-logr/logr"
	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
	appv1alpha1 "github.com/pdettori/kealm/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/klog/v2"
	workapiv1 "open-cluster-management.io/api/work/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

var (
	apiGVStr = schema.GroupVersion{Group: "apps", Version: "v1"}.String()
)

const (
	// AppBundleLabel is the label to add this resource to an appbundle
	AppBundleLabel = "cluster.open-cluster-management.io/appbundle"

	// DeployFinalizer is the finalizer for deployment
	DeployFinalizer = "controller.deployment.kcp.dev/finalizer"
)

// DeploymentReconciler reconciles a Deployment object
type DeploymentReconciler struct {
	client.Client
	Log    logr.Logger
	Scheme *runtime.Scheme
	CSet   *kubernetes.Clientset
}

// Reconcile -
func (r *DeploymentReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	deploy := &appsv1.Deployment{}
	if err := r.Get(ctx, req.NamespacedName, deploy); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	klog.Infof("Got deployment %s", req.Name)

	var aLabel *string
	if aLabel = getAppBundleLabel(*deploy); aLabel == nil {
		klog.Infof("No appbundle label found on deployment %s", deploy.Name)
		return ctrl.Result{}, nil
	}

	// check current status (does bundle exist ?)
	bundle := &appv1alpha1.AppBundle{}
	err := r.Get(ctx, types.NamespacedName{Namespace: req.Namespace, Name: *aLabel}, bundle)
	if err != nil {
		if apierrors.IsNotFound(err) {
			klog.Infof("AppBundle not found, please create new AppBundle")
		}
		return ctrl.Result{}, err
	}

	isPresent, isUptodate, updIndex, err := isDeploymentInAppBundle(deploy, bundle)
	if err != nil {
		return ctrl.Result{}, err
	}

	if !isPresent || (isPresent && !isUptodate) {
		appendOrUpdateDeploymentInAppBundle(deploy, bundle, updIndex)
		if err = r.Update(ctx, bundle, &client.UpdateOptions{}); err != nil {
			return ctrl.Result{}, err
		}
	}

	/*
		// examine DeletionTimestamp to determine if object is under deletion
		if deploy.ObjectMeta.DeletionTimestamp.IsZero() {
			// The object is not being deleted, so if it does not have our finalizer,
			// then lets add the finalizer and update the object. This is equivalent
			// registering our finalizer.
			if !containsString(deploy.GetFinalizers(), DeployFinalizer) {
				controllerutil.AddFinalizer(deploy, DeployFinalizer)
				klog.Infof(">>>> %+v", deploy)
				_, err := r.CSet.AppsV1().Deployments(deploy.Namespace).Update(ctx, deploy, v1.UpdateOptions{})
				if err != nil {
					return ctrl.Result{}, err
				}
			}
		} else {
			// The object is being deleted
			if containsString(deploy.GetFinalizers(), DeployFinalizer) {
				// our finalizer is present, so lets handle any external dependency
				// TODO - delete from appbundle
				// remove our finalizer from the list and update it.
				controllerutil.RemoveFinalizer(deploy, DeployFinalizer)
				_, err := r.CSet.AppsV1().Deployments(deploy.Namespace).Update(ctx, deploy, v1.UpdateOptions{})
				if err != nil {
					return ctrl.Result{}, IgnoreConflict(err)
				}
			}

			// Stop reconciliation as the item is being deleted
			return ctrl.Result{}, nil
		}

		// using the controller runtime client with deploy to update the status generated an error
		_, err = r.CSet.AppsV1().Deployments(deploy.Namespace).UpdateStatus(ctx, deploy, v1.UpdateOptions{})
		if err != nil {
			return ctrl.Result{}, err
		}
	*/

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *DeploymentReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&appsv1.Deployment{}).
		Complete(r)
}

// IgnoreConflict returns nil on Conflict errors, originating from updating when finalizer is deleted
// this is not a good practice but ok for finalizer here
func IgnoreConflict(err error) error {
	if apierrors.IsConflict(err) {
		return nil
	}
	return err
}

// Helper functions to check and remove string from a slice of strings.
func containsString(slice []string, s string) bool {
	for _, item := range slice {
		if item == s {
			return true
		}
	}
	return false
}

func removeString(slice []string, s string) (result []string) {
	for _, item := range slice {
		if item == s {
			continue
		}
		result = append(result, item)
	}
	return
}

func getAppBundleLabel(d appsv1.Deployment) *string {
	l, ok := d.GetLabels()[AppBundleLabel]
	if ok {
		return &l
	}
	return nil
}

func newAppBundle(name, namespace string, labels map[string]string) *appv1alpha1.AppBundle {
	ab := &appv1alpha1.AppBundle{
		ObjectMeta: v1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
			Labels:    labels,
		},
	}
	return ab
}

func isDeploymentInAppBundle(d *appsv1.Deployment, appBundle *appv1alpha1.AppBundle) (isPresent, isUpToDate bool, updIndex int, err error) {
	var manifest workapiv1.Manifest
	for updIndex, manifest = range appBundle.Spec.Workload.Manifests {
		var obj runtime.Object
		switch {
		case manifest.Object != nil:
			obj = manifest.Object
		default:
			obj, err = decodeUnstructured(manifest.Raw)
			if err != nil {
				return false, false, -1, err
			}
		}
		ma, err := meta.Accessor(obj)
		if err != nil {
			return false, false, -1, err
		}
		if d.Name == ma.GetName() && d.Namespace == ma.GetNamespace() {
			isPresent = true
			//target := obj.(*appsv1.Deployment)

			// if isSameDeployment(d, target) {
			// 	isUpToDate = true
			// }
			// TODO - work om comparing when using unstructured
			isUpToDate = true
			return isPresent, isUpToDate, updIndex, nil
		}
	}
	return false, false, -1, nil
}

func appendOrUpdateDeploymentInAppBundle(d *appsv1.Deployment, appBundle *appv1alpha1.AppBundle, updIndex int) {
	s := d.DeepCopy()
	delete(s.Annotations, "kubectl.kubernetes.io/last-applied-configuration")
	t := &appsv1.Deployment{
		TypeMeta: d.TypeMeta,
		ObjectMeta: v1.ObjectMeta{
			Name:        s.Name,
			Namespace:   s.Namespace,
			Labels:      s.Labels,
			Annotations: s.Annotations,
		},
		Spec: s.Spec,
	}
	m := workapiv1.Manifest{
		RawExtension: runtime.RawExtension{
			Object: t,
		},
	}
	if updIndex < 0 {
		appBundle.Spec.Workload.Manifests = append(appBundle.Spec.Workload.Manifests, m)
	} else {
		appBundle.Spec.Workload.Manifests[updIndex] = m
	}
}

func genDeploymentForManifest(d *appsv1.Deployment) *appsv1.Deployment {
	s := d.DeepCopy()
	return &appsv1.Deployment{
		TypeMeta: s.TypeMeta,
		ObjectMeta: v1.ObjectMeta{
			Name:        s.Name,
			Namespace:   s.Namespace,
			Labels:      s.Labels,
			Annotations: s.Annotations,
		},
		Spec: s.Spec,
	}
}

func isSameDeployment(source, target *appsv1.Deployment) bool {
	d := genDeploymentForManifest(source)
	diff := cmp.Diff(d, target, cmpopts.EquateEmpty())
	if diff == "" {
		return true
	}
	return false
}

func decodeUnstructured(data []byte) (*unstructured.Unstructured, error) {
	unstructuredObj := &unstructured.Unstructured{}
	err := unstructuredObj.UnmarshalJSON(data)
	if err != nil {
		return nil, fmt.Errorf("Failed to decode object: %w", err)
	}

	if err != nil {
		return nil, fmt.Errorf("Failed to find gvr from restmapping: %w", err)
	}

	return unstructuredObj, nil
}
