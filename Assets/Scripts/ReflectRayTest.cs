using UnityEngine;
using System.Collections;
using System.Collections.Generic;

[ExecuteInEditMode]
public sealed class ReflectRayTest : MonoBehaviour
{
    private void Update()
    {
        if (Input.GetMouseButton(0))
        {
            Ray r = Camera.main.ScreenPointToRay(Input.mousePosition);

            RaycastHit hitInfo;

            int layer = 1 << LayerMask.NameToLayer("Water");
            int layerMask = layer;

            bool ret = Physics.Raycast(r, out hitInfo, 1000, layerMask);

            if (ret)
            {
                Debug.DrawLine(r.origin, hitInfo.point, Color.red);

                Vector3 reflectRay = GetReflectRay(r, Vector3.up);
                Debug.DrawLine(hitInfo.point, hitInfo.point + reflectRay * 100, Color.green);
            }
        }
    }

    Vector3 GetReflectRay(Ray inputRay, Vector3 planeNormal)
    {
        Vector3 ret = -(2 * Vector3.Dot(inputRay.direction, planeNormal) * planeNormal - inputRay.direction);
        return ret.normalized;
    }
}