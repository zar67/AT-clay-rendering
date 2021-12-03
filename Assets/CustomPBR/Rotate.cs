using UnityEngine;

public class Rotate : MonoBehaviour
{
    [SerializeField] private float m_rotationSpeed = 5;

    private void Update()
    {
        Vector3 rotation = transform.rotation.eulerAngles;
        rotation.y += m_rotationSpeed * Time.deltaTime;
        transform.rotation = Quaternion.Euler(rotation);
    }
}
